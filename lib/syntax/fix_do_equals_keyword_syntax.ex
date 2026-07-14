defmodule Credence.Syntax.FixDoEqualsKeywordSyntax do
  @moduledoc """
  Fixes the syntax error where LLMs write `do = expr` instead of `do: expr`
  in keyword position (e.g., in `for` comprehensions or function definitions).

  LLMs use `do = expr` thinking it's assignment, but Elixir requires
  `do: expr` for keyword syntax. When a block also follows (`do = expr do ...
  end`), the fix converts to block form with the expression as the body.

  ## Bad (won't parse)

      def f(x), do = x + 1

      for x <- list, do = x + 1 do
        result
      end

  ## Good

      def f(x), do: x + 1

      for x <- list do
        x + 1
      end
  """

  use Credence.Syntax.Rule

  alias Credence.Issue

  # Matches `do =` in keyword position (preceded by a comma).
  @do_equals ~r/,\s*do\s*=\s*/

  # Compound pattern: `, do = expr do\n  body\nend`
  # When the LLM writes both keyword and block syntax together.
  @compound ~r/,\s*do\s*=\s*(\S.*?)\s+do\n(\s+)(.*?)\n(\s*)end/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if comment?(line) or not Regex.match?(@do_equals, line) do
        []
      else
        [build_issue(line_no)]
      end
    end)
  end

  @impl true
  def fix(source) do
    if Regex.match?(@compound, source) do
      Regex.replace(@compound, source, fn _match, expr, body_indent, _body, end_indent ->
        " do\n#{body_indent}#{expr}\n#{end_indent}end"
      end)
    else
      source
      |> String.split("\n")
      |> Enum.map_join("\n", fn line ->
        if comment?(line), do: line, else: Regex.replace(@do_equals, line, ", do: ")
      end)
    end
  end

  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_do_equals_keyword_syntax,
      message: "`do =` in keyword position should be `do:`",
      meta: %{line: line_no}
    }
  end
end
