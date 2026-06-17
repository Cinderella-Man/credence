defmodule Credence.Syntax.NoFnWithCapture do
  @moduledoc """
  Repairs `fn(&1 ...)` — the `fn` keyword mistakenly mixed with capture syntax.

  LLMs translating from other languages repeatedly emit `fn(&1 > 0)`, gluing the
  `fn` keyword onto a capture body. In Elixir `fn` opens a clause that needs
  `-> body end`, so `fn(&1 ...)` never parses — the compiler reports a mismatched
  delimiter (the `)` arrives where an `end` was expected). It is always a syntax
  error, so this is a REPAIR: the fix rewrites the leading `fn(` to `&(`,
  yielding the idiomatic capture form.

  Only `fn(` immediately followed by a capture variable (`&1`, `&2`, …) is
  touched — `fn(x) -> ... end` (parenthesised parameters) is valid Elixir and a
  capture variable can never legally appear in that position, so the match fires
  exclusively on the malformed shape.

  ## Bad (won't parse)

      Enum.filter(list, fn(&1 > 0))

  ## Good

      Enum.filter(list, &(&1 > 0))
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # `fn(` (standalone — not the tail of an identifier like `myfn(`) immediately
  # followed by a capture variable (`&1`, `&2`, …).
  @fn_capture_pattern ~r/\bfn\(&\d/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if fn_capture_line?(line) do
        [
          %Issue{
            rule: :no_fn_with_capture,
            message:
              "`fn(` followed by a capture variable is a parse error; " <>
                "use `&(...)` capture syntax instead.",
            meta: %{line: line_no}
          }
        ]
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
      if fn_capture_line?(line), do: fix_line(line), else: line
    end)
  end

  # `check` and `fix` share this one predicate, so they never disagree. Comment
  # lines are skipped: `fn(&1 ...)` inside a comment (or a heredoc body line that
  # starts with `#`) is text, not the parse error we repair — rewriting it would
  # corrupt non-code content of an already-broken file.
  defp fn_capture_line?(line) do
    not comment?(line) and Regex.match?(@fn_capture_pattern, line)
  end

  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)

  defp fix_line(line) do
    Regex.replace(@fn_capture_pattern, line, fn match ->
      String.replace_prefix(match, "fn(", "&(")
    end)
  end
end
