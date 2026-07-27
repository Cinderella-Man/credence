defmodule Credence.Syntax.NoAtomAsFunctionName do
  @moduledoc """
  Detects and fixes atom-literal-as-function-name syntax that won't parse in Elixir.

  LLMs repeatedly generate `:function_name(args)` — an atom literal followed by
  parentheses — which is a parse error (`syntax error before: '('`). This pattern
  is a common LLM hallucination, especially with ETS table names:

      :ets_table_name(name)
      :ets.whereis(:ets_table_name(name))

  The fix strips the leading colon, converting the atom to a bare function call:

      :ets_table_name(name) → ets_table_name(name)

  ## Bad (won't parse)

      :ets_table_name(__MODULE__)
      :my_helper(x, y)

  ## Good

      ets_table_name(__MODULE__)
      my_helper(x, y)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # An atom literal immediately followed by an opening parenthesis.
  #   group 1: the function name (word characters after the colon)
  # The colon must NOT be preceded by a word character (so `Module.:foo` is
  # matched, but `some_atom` without colon is not).
  @bad_pattern ~r/(?<!\w):(\w+)\(/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case Regex.run(@bad_pattern, line) do
        [_match, name] ->
          [
            %Issue{
              rule: :no_atom_as_function_name,
              message:
                "Atom `:#{name}` used as a function name — did you mean `#{name}(...)`?",
              meta: %{line: line_no}
            }
          ]

        nil ->
          []
      end
    end)
  end

  @impl true
  def fix(source) do
    Regex.replace(@bad_pattern, source, fn _match, name -> "#{name}(" end)
  end
end
