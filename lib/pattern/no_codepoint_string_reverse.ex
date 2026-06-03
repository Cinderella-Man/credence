defmodule Credence.Pattern.NoCodepointStringReverse do
  @moduledoc """
  Readability & performance rule: Detects
  `String.codepoints(s) |> Enum.reverse() |> IO.iodata_to_binary()` (and the
  `Enum.join/0` reassemble variant, and the nested call forms) which is a manual
  reimplementation of `String.reverse/1`.

  ## Safety: behind a switch

  Reversing a list of *codepoints* and gluing it back is **not** the same as
  `String.reverse/1` when a grapheme spans more than one codepoint — a decomposed
  accent, a ZWJ emoji, or a flag sequence would be torn apart. So this rule needs
  the `single_codepoint_graphemes` promise (see `Credence.Assumptions`): while it
  is on, every grapheme is a single codepoint, the codepoint list equals the
  grapheme list, and the rewrite is identical to the original. In `:strict` mode
  the rule does not run.

  This is the `String.codepoints/1` half of the split described in the safety
  plan (decision 4/12); the always-safe `String.graphemes/1` half lives in
  `Credence.Pattern.NoManualStringReverse`.

  ## Bad (only rewritten while `single_codepoint_graphemes` is on)

      reversed = str |> String.codepoints() |> Enum.reverse() |> IO.iodata_to_binary()
      reversed = str |> String.codepoints() |> Enum.reverse() |> Enum.join()
      reversed = IO.iodata_to_binary(Enum.reverse(String.codepoints(str)))

  ## Good

      reversed = String.reverse(str)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def assumptions, do: [:single_codepoint_graphemes]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline: ... |> String.codepoints() |> Enum.reverse() |> REASSEMBLE()
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

        # Nested call: REASSEMBLE(Enum.reverse(String.codepoints(s)))
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

  # Extracts the subject from String.codepoints in the middle of a pipe chain.
  defp decompose_in_middle({:|>, _, [subject, decompose]}) do
    if decompose_call?(decompose), do: {:ok, subject}, else: :error
  end

  defp decompose_in_middle({{:., _, [{:__aliases__, _, [:String]}, :codepoints]}, _, [subject]}) do
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

  # Decompose step: String.codepoints only (graphemes is a separate rule).
  defp decompose_call?(node), do: remote_call?(node, :String, :codepoints)

  defp reassemble_call?(node) do
    remote_call?(node, :Enum, :join) or remote_call?(node, :IO, :iodata_to_binary)
  end

  defp reassemble_fixable?(node) do
    (remote_call?(node, :Enum, :join) and join_no_separator?(node)) or
      remote_call?(node, :IO, :iodata_to_binary)
  end

  # Nested form: REASSEMBLE(Enum.reverse(String.codepoints(subject)))
  defp match_nested_manual_reverse(
         {{:., meta, [{:__aliases__, _, outer_mod}, outer_func]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _,
             [{{:., _, [{:__aliases__, _, [:String]}, :codepoints]}, _, [subject]}]}
          ]}
       )
       when outer_mod in [[:Enum], [:IO]] and outer_func in [:join, :iodata_to_binary] do
    {:ok, meta, subject}
  end

  defp match_nested_manual_reverse(_), do: :error

  defp build_issue(meta) do
    %Issue{
      rule: :no_codepoint_string_reverse,
      message:
        "Use `String.reverse/1` instead of manually decomposing a string into codepoints, " <>
          "reversing, and reassembling. It is clearer and handles Unicode correctly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
