defmodule Credence.Syntax.NoHashQuantifierInRegexSigil do
  @moduledoc """
  Repairs `\#{n,m}` quantifier syntax inside `~r/.../` regex sigils.

  LLMs write `\#{1,6}` inside `~r/.../` sigils (a Python raw-string habit),
  but `\#{` starts Elixir sigil interpolation and `1,6` is not a single
  expression — a parse error at the comma. Deterministic fix: wrap the `#`
  in a character class, `[#]{n,m}`, so it is a literal `#` followed by a
  regex quantifier — the same regex the author meant.

  ## Bad (won't parse)

      ~r/^\#{1,6}\\s+(.+)$/

  ## Good

      ~r/^[#]{1,6}\\s+(.+)$/

  ## Deliberately not flagged

  Only the *comma* forms (`\#{n,m}`, `\#{n,}`) are touched, because only
  those cannot parse. Everything else here is valid code whose meaning we
  refuse to change:

    * `~r/x\#{3}y/` — valid interpolation of the integer `3`; the regex is
      `x3y`, not "three hashes".
    * `~r/\#{1,6}/` (escaped hash) — already a literal `#` with a
      quantifier, and it parses.
    * `~R/\#{1,6}/` — `~R` does not interpolate, so it already parses.
    * Sigils with a delimiter other than `/` (`~r{...}`, `~r|...|`) — the
      fix only rewrites `/`-delimited bodies, so the check stays silent on
      them too.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # A `/`-delimited regex sigil, capturing its body. `\\.` keeps escaped
  # characters (notably `\/` and `\#`) inside the body.
  @sigil_re ~r/~r\/((?:[^\/\\]|\\.)*)\//

  # `#{digits,}` or `#{digits,digits}` — a regex quantifier masquerading as
  # Elixir interpolation. The comma is required: `#{3}` is valid
  # interpolation. The lookbehind skips `\#{...}`, which is already a
  # literal hash and already parses.
  @quantifier_re ~r/(?<!\\)#\{(\d+,\d*)\}/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if hash_quantifier_in_sigil?(line) do
        [
          %Issue{
            rule: :no_hash_quantifier_in_regex_sigil,
            message:
              "`\#{n,m}` inside a regex sigil starts interpolation and will not parse. " <>
                "Use `[#]{n,m}` for a literal `#` with a quantifier.",
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
    |> Enum.map_join("\n", &fix_line/1)
  end

  defp hash_quantifier_in_sigil?(line), do: fix_line(line) != line

  # Replace `#{n,m}` with `[#]{n,m}`, but only inside `~r/.../` sigil bodies.
  defp fix_line(line) do
    Regex.replace(@sigil_re, line, fn _full, body ->
      "~r/" <> Regex.replace(@quantifier_re, body, "[#]{\\1}") <> "/"
    end)
  end
end
