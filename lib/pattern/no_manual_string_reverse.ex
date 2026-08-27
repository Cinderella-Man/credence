defmodule Credence.Pattern.NoManualStringReverse do
  @moduledoc """
  Readability & performance rule: Detects the pattern
  `String.graphemes(s) |> Enum.reverse() |> Enum.join()` (and the
  `IO.iodata_to_binary/1` reassemble variant) which is a manual
  reimplementation of `String.reverse/1`.

  This rule covers only the **grapheme** decompose. Reversing a list of
  graphemes and gluing it back is identical to `String.reverse/1` for *every*
  input — graphemes are exactly what `String.reverse/1` reverses — so it needs
  no assumption and runs even in `:strict` mode. The `String.codepoints/1`
  variants are handled by `Credence.Pattern.NoCodepointStringReverse`, which
  needs the `single_codepoint_graphemes` promise (see decision 4: the split key
  is the *decompose* function, not the reassemble function).

  ## Bad

      reversed = str |> String.graphemes() |> Enum.reverse() |> Enum.join()
      reversed = str |> String.graphemes() |> Enum.reverse() |> IO.iodata_to_binary()
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
        # Pipeline: ... |> String.graphemes() |> Enum.reverse() |> REASSEMBLE()
        {:|>, meta, [left, right]} = node, issues ->
          if reassemble_fixable?(right) and remote_call?(rightmost(left), :Enum, :reverse) do
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

        # Nested call: REASSEMBLE(Enum.reverse(String.graphemes(s)))
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
      {:|>, _, [left, reassemble]} = node ->
        with true <- reassemble_fixable?(reassemble),
             {:|>, _, [middle, reverse]} <- left,
             true <- remote_call?(reverse, :Enum, :reverse),
             {:ok, subject} <- decompose_in_middle(middle) do
          fix_pipe_subject(subject)
        else
          _ -> node
        end

      node ->
        case match_nested_manual_reverse(node) do
          {:ok, _meta, subject} -> string_reverse_call(subject)
          :error -> node
        end
    end)
  end

  # Extracts the subject from String.graphemes in the middle of a pipe chain.
  defp decompose_in_middle({:|>, _, [subject, decompose]}) do
    if decompose_call?(decompose), do: {:ok, subject}, else: :error
  end

  defp decompose_in_middle({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}) do
    {:ok, subject}
  end

  defp decompose_in_middle(_), do: :error

  defp fix_pipe_subject({:|>, _, _} = pipe) do
    {:|>, [], [pipe, string_reverse_call()]}
  end

  defp fix_pipe_subject(subject) do
    string_reverse_call(subject)
  end

  defp string_reverse_call do
    {{:., [], [{:__aliases__, [], [:String]}, :reverse]}, [], []}
  end

  defp string_reverse_call(subject) do
    {{:., [], [{:__aliases__, [], [:String]}, :reverse]}, [], [subject]}
  end

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

  # Decompose step: String.graphemes only (codepoints is a separate rule).
  defp decompose_call?(node), do: remote_call?(node, :String, :graphemes)

  # The ONE reassembly predicate, shared by `check/2` and `fix_patches/2`:
  # `Enum.join` with no separator (or an empty one), or
  # `IO.iodata_to_binary` with no explicit pipeline arguments.
  #
  # `check/2` had its own arity-blind `reassemble_call?/1` accepting `Enum.join`
  # with ANY argument, so `s |> String.graphemes() |> Enum.reverse() |> Enum.join("-")`
  # was reported and never repaired. It is not a manual `String.reverse/1` at all:
  # that pipeline interleaves the separator, and `String.reverse/1` produces none.
  # The only order-preserving alternative is longer than the original AND
  # reintroduces the `String.graphemes/1` this rule exists to remove, so there is
  # nothing to rewrite into. Same defect and same repair as the sibling
  # `NoCodepointStringReverse`.
  defp reassemble_fixable?(node) do
    (remote_call?(node, :Enum, :join) and join_no_separator?(node)) or
      match?({{:., _, [{:__aliases__, _, [:IO]}, :iodata_to_binary]}, _, []}, node)
  end

  # Nested form: REASSEMBLE(Enum.reverse(String.graphemes(subject)))
  defp match_nested_manual_reverse(
         {{:., meta, [{:__aliases__, _, outer_mod}, outer_func]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
             [{{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, [subject]}]}
          ]}
       )
       when (outer_mod == [:Enum] and outer_func == :join) or
              (outer_mod == [:IO] and outer_func == :iodata_to_binary) do
    {:ok, meta, subject}
  end

  defp match_nested_manual_reverse(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_string_reverse,
      message:
        "Use `String.reverse/1` instead of manually decomposing a string into graphemes, " <>
          "reversing, and reassembling. It is clearer and handles Unicode correctly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
