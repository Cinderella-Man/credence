defmodule Credence.Rule.NoStringLengthForCharCheck do
  @moduledoc """
  Performance rule: Detects `String.length(x) == 1` (or `!= 1`) used to
  validate that a string is a single character.

  `String.length/1` traverses the entire string to count grapheme clusters,
  making it O(n). For a simple single-character check, pattern matching on
  the result of `String.graphemes/1` or using `String.to_charlist/1` is more
  efficient and expressive.

  ## Bad

      if String.length(target_char) != 1 do
        raise ArgumentError, "expected a single character"
      end

  ## Good

      case String.graphemes(target_char) do
        [_single] -> :ok
        _ -> raise ArgumentError, "expected a single character"
      end

      # Or use a function head with a guard on byte_size for ASCII:
      def count_char(string, <<_::utf8>> = target) do
        ...
      end
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match: String.length(x) == 1, String.length(x) != 1,
        #        String.length(x) === 1, String.length(x) !== 1
        {op, meta,
         [
           {{:., _, [{:__aliases__, _, [:String]}, :length]}, _, [_arg]},
           1
         ]} = node,
        issues
        when op in [:==, :!=, :===, :!==] ->
          {node, [build_issue(meta) | issues]}

        # Match the reversed form: 1 == String.length(x)
        {op, meta,
         [
           1,
           {{:., _, [{:__aliases__, _, [:String]}, :length]}, _, [_arg]}
         ]} = node,
        issues
        when op in [:==, :!=, :===, :!==] ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_string_length_for_char_check,
      severity: :info,
      message:
        "`String.length/1` traverses the entire string (O(n)) just to check for a single character. " <>
          "Use pattern matching (e.g. `<<_::utf8>>`) or `String.graphemes/1` with a match instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
