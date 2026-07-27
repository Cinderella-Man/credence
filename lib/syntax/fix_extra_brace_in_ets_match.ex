defmodule Credence.Syntax.FixExtraBraceInEtsMatch do
  @moduledoc """
  Repairs the extra `}` before `)` in ETS match/2/3 pattern arguments.

  LLMs frequently emit `"$2"}})` instead of `"$2"})` in ETS match spec
  patterns — an extra closing brace before the call's closing parenthesis.
  This mismatches delimiters, prevents parsing, and no existing syntax rule
  targets it.

  A deterministic text-level replacement of `"}})`  → `"})` repairs the error.

  ## Bad (won't parse — mismatched delimiter)

      :ets.match(table, {{name, :"$1"}, :"$2"}})

  ## Good

      :ets.match(table, {{name, :"$1"}, :"$2"})
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @pattern "\"}})"
  @replacement "\"})"

  @impl true
  def analyze(source) do
    if unparseable?(source) and String.contains?(source, @pattern) do
      [
        %Issue{
          rule: :fix_extra_brace_in_ets_match,
          message:
            "Extra `}` before `)` in ETS match spec pattern — `\"}})` should be `\"})`.",
          meta: %{line: detect_line(source)}
        }
      ]
    else
      []
    end
  end

  @impl true
  def fix(source) do
    String.replace(source, @pattern, @replacement)
  end

  defp unparseable?(source) do
    match?({:error, _}, Code.string_to_quoted(source))
  end

  defp detect_line(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.find_value(fn {line, line_no} ->
      if String.contains?(line, @pattern), do: line_no
    end)
  end
end
