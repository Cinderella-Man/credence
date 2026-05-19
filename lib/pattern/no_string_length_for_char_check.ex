defmodule Credence.Pattern.NoStringLengthForCharCheck do
  @moduledoc """
  Performance rule: Detects `String.length(x) == 1` (or `!= 1`) used to
  validate that a string is a single character.
  `String.length/1` traverses the entire string to count grapheme clusters,
  making it O(n). For a simple single-character check, pattern matching on
  the result of `String.graphemes/1` is more expressive and idiomatic.
  This rule automatically rewrites the comparison to use `match?/2` with
  `String.graphemes/1`, which produces a clean boolean result that works
  in any expression context.
  ## Bad
      if String.length(target_char) != 1 do
        raise ArgumentError, "expected a single character"
      end
      String.length(s) == 1
      1 === String.length(s)
  ## Good
      if not match?([_], String.graphemes(target_char)) do
        raise ArgumentError, "expected a single character"
      end
      match?([_], String.graphemes(s))
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {op, _meta, [lhs, rhs]} = node, issues when op in [:==, :!=, :===, :!==] ->
          cond do
            string_length_call?(lhs) and int_one?(rhs) -> {node, [build_issue(node) | issues]}
            int_one?(lhs) and string_length_call?(rhs) -> {node, [build_issue(node) | issues]}
            true -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {op, _meta, [lhs, rhs]} = node when op in [:==, :!=, :===, :!==] ->
        cond do
          string_length_call?(lhs) and int_one?(rhs) -> build_fix(op, length_arg(lhs))
          int_one?(lhs) and string_length_call?(rhs) -> build_fix(op, length_arg(rhs))
          true -> node
        end

      node ->
        node
    end)
  end

  defp string_length_call?({{:., _, [{:__aliases__, _, [:String]}, :length]}, _, [_]}), do: true
  defp string_length_call?(_), do: false

  defp length_arg({{:., _, [{:__aliases__, _, [:String]}, :length]}, _, [arg]}), do: arg

  defp int_one?(1), do: true
  defp int_one?({:__block__, _, [1]}), do: true
  defp int_one?(_), do: false

  # ==, === → match?([_], String.graphemes(x))
  # !=, !== → not match?([_], String.graphemes(x))
  defp build_fix(op, arg) when op in [:==, :===] do
    match_graphemes_one(arg)
  end

  defp build_fix(op, arg) when op in [:!=, :!==] do
    {:not, [], [match_graphemes_one(arg)]}
  end

  defp match_graphemes_one(arg) do
    graphemes_call = {{:., [], [{:__aliases__, [], [:String]}, :graphemes]}, [], [arg]}
    {:match?, [], [[{:_, [], nil}], graphemes_call]}
  end

  defp build_issue(node) do
    meta = elem(node, 1)

    %Issue{
      rule: :no_string_length_for_char_check,
      message:
        "`String.length/1` traverses the entire string (O(n)) just to check for a single character. " <>
          "Use pattern matching (e.g. `<<_::utf8>>`) or `String.graphemes/1` with a match instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
