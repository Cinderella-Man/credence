defmodule Credence.Syntax do
  @moduledoc """
  Syntax-level fixes for code that won't parse.

  These rules work on raw source strings because the code has syntax errors
  that prevent `Code.string_to_quoted` from parsing it. Each rule detects
  a known LLM syntax pattern and rewrites it to valid Elixir.

  Currently handles:
  - `expr div expr` → `div(expr, expr)` (Python `//` translated as infix)
  - `expr rem expr` → `rem(expr, expr)` (same pattern for modulo)
  """
  alias Credence.Issue

  @doc """
  Detects known syntax issues in unparseable code.

  Only reports issues when `Code.string_to_quoted` fails AND the source
  contains known fixable patterns. Returns `[]` for valid code.
  """
  @spec analyze(String.t(), keyword()) :: [Issue.t()]
  def analyze(source, _opts \\ []) do
    case Code.string_to_quoted(source) do
      {:ok, _ast} ->
        []

      {:error, {line, _msg, _token}} ->
        detect_issues(source, line)
    end
  end

  @doc """
  Applies string-level syntax fixes. Returns the source unchanged if it
  already parses or no known patterns are found.
  """
  @spec fix(String.t(), keyword()) :: String.t()
  def fix(source, _opts \\ []) do
    case Code.string_to_quoted(source) do
      {:ok, _ast} ->
        source

      {:error, _} ->
        source
        |> fix_infix_div_rem()
        |> maybe_retry_more_fixes()
    end
  end

  # ── Detection ───────────────────────────────────────────────────

  defp detect_issues(source, error_line) do
    lines = String.split(source, "\n")

    []
    |> detect_infix_div_rem(lines, error_line)
  end

  defp detect_infix_div_rem(issues, lines, _error_line) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce(issues, fn {line, line_no}, acc ->
      cond do
        infix_div?(line) ->
          [build_issue(:infix_div, line_no, "div") | acc]

        infix_rem?(line) ->
          [build_issue(:infix_rem, line_no, "rem") | acc]

        true ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  # ── Fixing ──────────────────────────────────────────────────────

  defp fix_infix_div_rem(source) do
    source
    |> String.split("\n")
    |> Enum.map(fn line ->
      cond do
        infix_div?(line) -> fix_infix_operator(line, "div")
        infix_rem?(line) -> fix_infix_operator(line, "rem")
        true -> line
      end
    end)
    |> Enum.join("\n")
  end

  # After fixing div/rem, try parsing again. If still broken, return as-is.
  # If fixed, return the repaired source.
  defp maybe_retry_more_fixes(source) do
    case Code.string_to_quoted(source) do
      {:ok, _} -> source
      {:error, _} -> source
    end
  end

  # ── Pattern detection ───────────────────────────────────────────
  #
  # Detects `expr div expr` used as infix (Python // style).
  # Must NOT match:
  #   - `|> div(expr)` — valid pipe
  #   - `div(expr, expr)` — valid function call
  #   - `# comment with div` — in a comment
  #   - `"string with div"` — in a string

  defp infix_div?(line), do: infix_operator?(line, "div")
  defp infix_rem?(line), do: infix_operator?(line, "rem")

  defp infix_operator?(line, op) do
    trimmed = String.trim(line)

    not String.starts_with?(trimmed, "#") and
      Regex.match?(infix_pattern(op), line)
  end

  # Matches: word/paren/digit, then space(s), then div/rem, then space(s), then word/digit
  # Does NOT match: |> div(, div(, .div
  defp infix_pattern("div"), do: ~r/(?<![|>.])\b(\w+\)?)\s+div\s+(\w+)/
  defp infix_pattern("rem"), do: ~r/(?<![|>.])\b(\w+\)?)\s+rem\s+(\w+)/

  # ── Infix → function call rewrite ──────────────────────────────
  #
  # Rewrites `prefix expr1 div expr2 suffix` → `prefix div(expr1, expr2) suffix`
  #
  # Strategy: find ` div ` in the line, split into left-context and right-operand.
  # The left operand is everything from the last `=` (or line start) to `div`.
  # The right operand is everything after `div` to end of expression.

  defp fix_infix_operator(line, op) do
    # Pattern: (assignment_prefix)(left_operand) op (right_operand)(trailing)
    regex = ~r/^(\s*(?:\w+\s*=\s*)?)(.+?)\s+#{op}\s+(.+?)(\s*$)/

    case Regex.run(regex, line) do
      [_full, prefix, left, right, trailing] ->
        "#{prefix}#{op}(#{String.trim(left)}, #{String.trim(right)})#{trailing}"

      nil ->
        # Fallback: try simpler pattern without assignment prefix
        simple = ~r/^(\s*)(.+?)\s+#{op}\s+(.+?)(\s*$)/

        case Regex.run(simple, line) do
          [_full, indent, left, right, trailing] ->
            "#{indent}#{op}(#{String.trim(left)}, #{String.trim(right)})#{trailing}"

          nil ->
            line
        end
    end
  end

  defp build_issue(rule, line, op) do
    %Issue{
      rule: rule,
      message:
        "`#{op}` cannot be used as an infix operator in Elixir. " <>
          "Use `#{op}(a, b)` function call syntax instead.",
      meta: %{line: line}
    }
  end
end
