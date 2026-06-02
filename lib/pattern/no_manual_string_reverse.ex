defmodule Credence.Pattern.NoManualStringReverse do
  @moduledoc """
  Readability & performance rule: Detects the pattern
  `String.graphemes(s) |> Enum.reverse() |> Enum.join()` (and variants using
  `String.codepoints/1` or `IO.iodata_to_binary/1`) which is a manual
  reimplementation of `String.reverse/1`.

  `String.reverse/1` handles Unicode grapheme clusters correctly and avoids
  creating an intermediate list, making it both clearer and faster.

  ## Bad

      # In a pipeline with graphemes + join
      reversed = str |> String.graphemes() |> Enum.reverse() |> Enum.join()

      # Using codepoints + IO.iodata_to_binary
      reversed = str |> String.codepoints() |> Enum.reverse() |> IO.iodata_to_binary()

      # As a nested call
      reversed = Enum.join(Enum.reverse(String.graphemes(str)))

  ## Good

      reversed = String.reverse(str)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline form: ... |> String.graphemes() |> Enum.reverse() |> Enum.join()
        #
        # `a |> b() |> c()` parses as {:|>, _, [{:|>, _, [a, b]}, c]}.
        # So the outer pipe has `c` on the right and the inner chain on the left.
        # We check: right == Enum.join, predecessor == Enum.reverse, predecessor's predecessor == String.graphemes.
        {:|>, meta, [left, right]} = node, issues ->
          if reassemble_call?(right) and remote_call?(rightmost(left), :Enum, :reverse) do
            grandparent =
              case left do
                {:|>, _, [inner_left, _]} -> rightmost(inner_left)
                _ -> nil
              end

            if grandparent != nil and decompose_call?(grandparent) do
              {node, [build_issue(meta) | issues]}
            else
              {node, issues}
            end
          else
            {node, issues}
          end

        # Nested call form: REASSEMBLE(Enum.reverse(DECOMPOSE(s)))
        node, issues ->
          case match_nested_manual_reverse(node) do
            {:ok, meta, _subject} -> {node, [build_issue(meta) | issues]}
            :error -> {node, issues}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Pipeline: ... |> String.graphemes() |> Enum.reverse() |> Enum.join()
      #
      # Matches the outermost `|>` whose right side is Enum.join(),
      # then verifies the two preceding pipe stages are Enum.reverse()
      # and String.graphemes().  Only fires when Enum.join has no
      # explicit separator (safe replacement).
      {:|>, _, [left, join]} = node ->
        with true <- reassemble_fixable?(join),
             {:|>, _, [middle, reverse]} <- left,
             true <- remote_call?(reverse, :Enum, :reverse),
             {:ok, subject} <- decompose_in_middle(middle) do
          fix_pipe_subject(subject)
        else
          _ -> node
        end

      # Nested: REASSEMBLE(Enum.reverse(DECOMPOSE(s)))
      node ->
        case match_nested_manual_reverse(node) do
          {:ok, _meta, subject} -> string_reverse_call(subject)
          :error -> node
        end
    end)
  end

  # Extracts the subject from String.graphemes/codepoints in the middle of a pipe chain.
  # Handles both `subject |> String.graphemes()` and `String.graphemes(subject)`.
  defp decompose_in_middle({:|>, _, [subject, decompose]}) do
    if decompose_call?(decompose), do: {:ok, subject}, else: :error
  end

  defp decompose_in_middle({{:., _, [{:__aliases__, _, [:String]}, func]}, _, [subject]})
       when func in [:graphemes, :codepoints] do
    {:ok, subject}
  end

  defp decompose_in_middle(_), do: :error

  # When the subject is already a pipeline, append String.reverse() at the end.
  # Otherwise wrap in a direct call: String.reverse(subject).
  defp fix_pipe_subject({:|>, _, _} = pipe) do
    {:|>, [], [pipe, string_reverse_call()]}
  end

  defp fix_pipe_subject(subject) do
    string_reverse_call(subject)
  end

  # AST for `String.reverse()` (no args – value arrives via pipe)
  defp string_reverse_call do
    {{:., [], [{:__aliases__, [], [:String]}, :reverse]}, [], []}
  end

  # AST for `String.reverse(subject)`
  defp string_reverse_call(subject) do
    {{:., [], [{:__aliases__, [], [:String]}, :reverse]}, [], [subject]}
  end

  # Safe to auto-fix when Enum.join has no separator or an empty-string
  # separator (which is the default). A non-empty separator would change
  # semantics (e.g. Enum.join(list, "-") ≠ String.reverse).
  defp join_no_separator?({{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, []}), do: true

  defp join_no_separator?({{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [sep]}),
    do: empty_string_literal?(sep)

  defp join_no_separator?(_), do: false

  defp empty_string_literal?(""), do: true
  defp empty_string_literal?({:__block__, _, [""]}), do: true
  defp empty_string_literal?(_), do: false

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  # Decompose step: String.graphemes or String.codepoints
  defp decompose_call?(node) do
    remote_call?(node, :String, :graphemes) or remote_call?(node, :String, :codepoints)
  end

  # Reassemble step: Enum.join or IO.iodata_to_binary (for check — any args)
  defp reassemble_call?(node) do
    remote_call?(node, :Enum, :join) or remote_call?(node, :IO, :iodata_to_binary)
  end

  # Reassemble step that is safe to auto-fix (Enum.join without separator, or IO.iodata_to_binary)
  defp reassemble_fixable?(node) do
    (remote_call?(node, :Enum, :join) and join_no_separator?(node)) or
      remote_call?(node, :IO, :iodata_to_binary)
  end

  # Match nested form: REASSEMBLE(Enum.reverse(DECOMPOSE(subject)))
  defp match_nested_manual_reverse(
         {{:., meta, [{:__aliases__, _, outer_mod}, outer_func]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
             [{{:., _, [{:__aliases__, _, [:String]}, inner_func]}, _, [subject]}]}
          ]}
       )
       when outer_mod in [[:Enum], [:IO]] and outer_func in [:join, :iodata_to_binary] and
              inner_func in [:graphemes, :codepoints] do
    {:ok, meta, subject}
  end

  defp match_nested_manual_reverse(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_string_reverse,
      message:
        "Use `String.reverse/1` instead of manually decomposing a string into graphemes/codepoints, " <>
          "reversing, and reassembling. It is clearer and handles Unicode correctly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
