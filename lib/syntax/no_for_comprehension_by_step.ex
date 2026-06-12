defmodule Credence.Syntax.NoForComprehensionByStep do
  @moduledoc """
  Detects and rewrites Python-style `for x <- range by step` syntax.

  LLMs translating from Python may emit `for x <- start..end by step`,
  which is invalid Elixir syntax — the `by` keyword does not exist in
  `for` comprehensions.  The idiomatic Elixir equivalent uses
  `Stream.iterate/2` piped into `Stream.take_while/2`:

      # BEFORE (invalid)
      for x <- base..(limit - 1) by base do
        x
      end

      # AFTER (valid)
      for x <- Stream.iterate(base, &(&1 + base))
              |> Stream.take_while(&(&1 <= (limit - 1))) do
        x
      end

  The rewrite is safe because the before snippet never parses — there is
  no risk of changing runtime behaviour.  The after snippet produces a
  list of the same values that the intended stepped range would yield.

  ## Detected patterns

      for x <- expr..expr by step do
      for x <- expr..expr by step end

  ## Not flagged

  Valid `for` comprehensions without `by`:

      for x <- 1..10, do: x
      for x <- list, do: x * 2

  Legitimate occurrences of `by` elsewhere (e.g. variable names):

      for byte <- bytes, do: byte   # `byte` is fine, not `by`

  # Regex internals

  The pattern matches:
    `for` + `<enumerators>` + `<start>..<end>` + ` by ` + `<step>` + (`do` | `end`)
  where the range expression contains `..`.
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches: for ... <- start..end_expr by step do/end
  # Group 1: prefix (for ... <-)
  # Group 2: start of range
  # Group 3: end of range expression (may include parens, e.g. "(limit - 1)")
  # Group 4: step value
  # Group 5: whitespace before do/end
  # Group 6: closing keyword (do or end)
  @for_by_pattern ~r/(for\b.*?<-\s*)(.*?)\.\.([\S\s]*?)\s+by\s+(\S+)(\s*)(do|end)\b/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@for_by_pattern, line) do
        [build_issue(line_no)]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if Regex.match?(@for_by_pattern, line), do: fix_line(line), else: line
    end)
  end

  defp fix_line(line) do
    Regex.replace(@for_by_pattern, line, fn _match, prefix, start, end_expr, step, ws, kw ->
      "#{prefix}Stream.iterate(#{start}, &(&1 + #{step}))" <>
        " |> Stream.take_while(&(&1 <= #{end_expr}))#{ws}#{kw}"
    end)
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :no_for_comprehension_by_step,
      message:
        "Python-style `for x <- range by step` is not valid Elixir. " <>
          "Use `Stream.iterate/2` + `Stream.take_while/2` instead.",
      meta: %{line: line_no}
    }
  end
end
