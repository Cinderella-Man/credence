defmodule Credence.Syntax.FixEtsMatchSpecErlangLessThan do
  @moduledoc """
  Replaces the unparseable bare atom `:=<` with the quoted `:"=<"` for
  Erlang-compatible ETS match spec guards.

  LLMs frequently write Erlang's less-than-or-equal as the bare atom `:=<` in
  ETS match spec guards.  In Elixir, `=<` is not a recognised operator, so
  `:=<` is tokenised as the match operator `=` followed by `<` — a syntax
  error.  The correct Elixir form is the quoted atom `:"=<"`, which maps to the
  Erlang `=<` operator that ETS match specs expect.

  A deterministic text-level replacement of `:=<` → `:"=<"` repairs the error.

  ## Bad (won't parse)

      guards = [{:=<, :"$1", cutoff}]

  ## Good

      guards = [{:"=<", :"$1", cutoff}]
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @pattern ":=<"

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if String.contains?(line, @pattern) do
        [
          %Issue{
            rule: :fix_ets_match_spec_erlang_less_than,
            message:
              "Bare atom `:=<` is not valid Elixir. Use `:\"=<\"` for less-than-or-equal in ETS match specs.",
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
    String.replace(source, @pattern, ~s(:"=<"))
  end
end
