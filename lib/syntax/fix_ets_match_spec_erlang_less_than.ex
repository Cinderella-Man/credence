defmodule Credence.Syntax.FixEtsMatchSpecErlangLessThan do
  @moduledoc """
  Replaces the unparseable Erlang-style `:=<` atom with Elixir's `:<=`.

  LLMs consistently write Erlang-style `:=<` (less-than-or-equal) in ETS match
  spec guards instead of Elixir's `:<=`.  In Elixir, `:=<` is tokenised as the
  match operator `=` followed by the less-than operator `<`, which causes a
  syntax error — the parser cannot make sense of the sequence in an atom
  position.

  A deterministic text-level replacement of `:=<` → `:<=` repairs the error.

  ## Bad (won't parse)

      guards = [{:=<, :"$1", cutoff}]

  ## Good

      guards = [{:<=, :"$1", cutoff}]
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
              "Erlang-style `:=<` is not valid Elixir. Use `:<=` for less-than-or-equal in ETS match specs.",
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
    String.replace(source, @pattern, ":<=")
  end
end
