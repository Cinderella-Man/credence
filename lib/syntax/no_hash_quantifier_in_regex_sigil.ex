defmodule Credence.Syntax.NoHashQuantifierInRegexSigil do
  @moduledoc """
  Repairs `\#{...}` quantifier syntax inside `~r` regex sigils.

  LLMs write `\#{1,6}` inside `~r/.../` sigils (a Python raw-string habit),
  but `\#{` triggers Elixir sigil interpolation — a parse error at the comma.
  Deterministic fix: wrap the `#` in a character class `[#]{...}` so it is a
  literal hash followed by a regex quantifier. Behaviour-identical on all inputs
  (both match a literal `#` repeated 1–6 times).

  ## Bad (won't parse)

      ~r/^\#{1,6}\s+(.+)$/

  ## Good

      ~r/^[#]{1,6}\s+(.+)$/
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Matches #{digits} or #{digits,digits} — regex quantifier masquerading as
  # Elixir interpolation.
  @quantifier_re ~r/#\{(\d+(?:,\d*)?)\}/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if in_regex_sigil_with_quantifier?(line) do
        [
          %Issue{
            rule: :no_hash_quantifier_in_regex_sigil,
            message:
              "`\#{...}` inside a regex sigil triggers interpolation. " <>
                "Use `[#]{...}` for a literal `#` with a quantifier.",
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
    if Regex.match?(~r/~r[^\w\s@].*#\{\d/, source) do
      fix_regex_sigils(source)
    else
      source
    end
  end

  defp in_regex_sigil_with_quantifier?(line) do
    Regex.match?(~r/~r[^\w\s@].*#\{\d+(?:,\d*)?\}/, line)
  end

  # Replace #{quantifier} with [#]{quantifier} inside ~r/.../ sigil bodies.
  # Handles escaped characters (e.g. \/) inside the body.
  defp fix_regex_sigils(source) do
    Regex.replace(~r/(~r)\/((?:[^\/\\]|\\.)*)\//s, source, fn _full, prefix, body ->
      fixed_body = Regex.replace(@quantifier_re, body, "[#]{\\1}")
      prefix <> "/" <> fixed_body <> "/"
    end)
  end
end
