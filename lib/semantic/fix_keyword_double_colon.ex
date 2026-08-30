defmodule Credence.Semantic.FixKeywordDoubleColon do
  @moduledoc """
  Fixes the compiler error when `::` (type-annotation operator) is used
  instead of `:` (keyword syntax) in keyword arguments.

  LLMs write `name::expr` in keyword arguments, confusing the `::`
  type-annotation operator with `:` keyword syntax. The compiler emits:

      misplaced operator ::/2

  The fix replaces the `::` at the diagnostic location with `: `.

  ## Matching vs fixing

  `match?/1` sees only the diagnostic (no source), so it claims every
  `misplaced operator ::/2` error; `fix/2` then verifies the source actually
  has the fixable shape and no-ops otherwise, and the `should_report?/2`
  phase hook keeps `analyze` honest by reporting an issue only when the fix
  would rewrite the source.

  ## Deliberately skipped (no fix)

  - Diagnostics whose column does not sit on a literal `::` (e.g. a spaced
    `name :: value`, or a position format this rule does not understand):
    splicing `: ` in blind would corrupt the line.
  - Sites where swapping `::` for `: ` does not yield parseable code, such
    as non-keyword contexts (`y = x::integer` would become the syntax error
    `y = x: integer`) or a line with a second `::` after the reported one
    (`foo(a: 1, b::2)` is "unexpected expression after keyword list"). The
    fix parses its candidate output and returns the source unchanged unless
    the rewrite parses.

  ## Bad

      defmodule CredenceKwDoubleColonAnalyzeFixtureFKDC do
        use GenServer

        def start do
          GenServer.start_link(__MODULE__, :ok, name::CredenceKwDoubleColonName)
        end

        def init(state), do: {:ok, state}
      end

  ## Good

      defmodule CredenceKwDoubleColonAnalyzeFixtureFKDC do
        use GenServer

        def start do
          GenServer.start_link(__MODULE__, :ok, name: CredenceKwDoubleColonName)
        end

        def init(state), do: {:ok, state}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "misplaced operator ::/2"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source, so unfixable `misplaced
  operator ::/2` sites are not attributed to this rule.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_keyword_double_colon,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{position: {line_num, col}})
      when is_integer(line_num) and line_num > 0 and is_integer(col) and col > 0 do
    lines = String.split(source, "\n")

    # Compiler columns are grapheme-aligned (verified against combining
    # accents and multi-codepoint emoji), so String.slice indexes match.
    with line_str when is_binary(line_str) <- Enum.at(lines, line_num - 1),
         "::" <- String.slice(line_str, col - 1, 2) do
      before_col = String.slice(line_str, 0, col - 1)
      after_col = String.slice(line_str, col + 1, String.length(line_str))
      new_line = before_col <> ": " <> after_col
      fixed = lines |> List.replace_at(line_num - 1, new_line) |> Enum.join("\n")

      case Sourceror.parse_string(fixed) do
        {:ok, _} -> fixed
        _ -> source
      end
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
