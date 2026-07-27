defmodule Credence.Syntax.FixStrayCommaBeforeWhenGuard do
  @moduledoc """
  Fixes a stray comma between a function clause's closing parenthesis and
  the `when` guard keyword.

  LLMs sometimes insert a comma between the parameter list and the `when`
  guard (e.g. `def f(x), when x > 0`), producing a "syntax error before:
  when" that the parser cannot recover from. The intended code has no
  comma — the guard follows the closing parenthesis directly.

  ## Bad (won't parse)

      def positive?(x),
        when x > 0, do: true

  ## Good

      def positive?(x) when x > 0, do: true
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches `)` followed by a comma, optional whitespace (including newlines),
  # and the `when` keyword. The word boundary after `when` avoids matching
  # identifiers like `whenever`.
  @stray_comma ~r/\),\s*when\b/s

  @impl true
  def analyze(source) do
    @stray_comma
    |> Regex.scan(source, return: :index)
    |> Enum.map(fn [{match_pos, _match_len} | _] ->
      line = source |> binary_part(0, match_pos) |> String.split("\n") |> length()

      %Issue{
        rule: :fix_stray_comma_before_when_guard,
        message:
          "Stray comma before `when` guard. " <>
            "Remove the comma between `)` and `when`.",
        meta: %{line: line}
      }
    end)
  end

  @impl true
  def fix(source) do
    Regex.replace(@stray_comma, source, ") when")
  end
end
