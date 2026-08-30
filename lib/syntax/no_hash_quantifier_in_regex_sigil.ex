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

  alias Credence.{Issue, SourceMask}

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
    |> quantifier_matches()
    |> Enum.map(fn {start, _length, _replacement} -> line_number(source, start) end)
    |> Enum.uniq()
    |> Enum.map(fn line_no ->
      %Issue{
        rule: :no_hash_quantifier_in_regex_sigil,
        message:
          "`\#{n,m}` inside a regex sigil starts interpolation and will not parse. " <>
            "Use `[#]{n,m}` for a literal `#` with a quantifier.",
        meta: %{line: line_no}
      }
    end)
  end

  @impl true
  def fix(source) do
    source
    |> quantifier_matches()
    |> Enum.reverse()
    |> Enum.reduce(source, fn {start, length, replacement}, acc ->
      <<head::binary-size(^start), _::binary-size(^length), tail::binary>> = acc
      head <> replacement <> tail
    end)
  end

  defp quantifier_matches(source) do
    @sigil_re
    |> Regex.scan(source, return: :index)
    |> Enum.filter(fn [{sigil_start, _sigil_length}, _body] ->
      code_sigil_opener?(source, sigil_start)
    end)
    |> Enum.flat_map(fn [_sigil, {body_start, body_length}] ->
      body = binary_part(source, body_start, body_length)

      Regex.scan(@quantifier_re, body, return: :index)
      |> Enum.map(fn [{start, length}, {range_start, range_length}] ->
        range = binary_part(body, range_start, range_length)
        {body_start + start, length, "[#]{" <> range <> "}"}
      end)
    end)
  end

  # Masking the source only through `~r` leaves a real opener visible as code,
  # while the same bytes inside a comment or literal are already blanked.
  defp code_sigil_opener?(source, start) do
    prefix = binary_part(source, 0, start + 2)
    String.ends_with?(SourceMask.mask(prefix), "~r")
  end

  defp line_number(source, offset) do
    source
    |> binary_part(0, offset)
    |> String.split("\n")
    |> length()
  end
end
