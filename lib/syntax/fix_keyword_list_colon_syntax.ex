defmodule Credence.Syntax.FixKeywordListColonSyntax do
  @moduledoc """
  Fixes the syntax error where LLMs write `:key: value` instead of `key: value`
  inside keyword lists (a Python/JS colon-on-wrong-side idiom).

  LLMs frequently emit `:read_concurrency: true` (atom prefix + keyword colon)
  instead of the correct `read_concurrency: true` (keyword syntax). The pattern
  `:identifier:` followed by whitespace is never valid Elixir — the leading colon
  signals an atom, and the trailing colon attempts keyword syntax, producing a
  parse error.

  ## Bad (won't parse)

      :ets.new(table_name, [:set, :named_table, :public, :read_concurrency: true])

  ## Good

      :ets.new(table_name, [:set, :named_table, :public, read_concurrency: true])
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches `:identifier:` followed by whitespace — the colon-on-wrong-side idiom.
  # `:identifier` alone is a valid atom, but `:identifier:` is never valid Elixir.
  #
  # Group 1: the identifier (e.g. `read_concurrency`)
  # Group 2: the whitespace after the second colon
  @pattern ~r/:([a-z_][a-zA-Z0-9_]*[?!]?):(\s)/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if comment_line?(line) do
        []
      else
        case Regex.run(@pattern, line) do
          [_match, identifier, _space] -> [build_issue(line_no, identifier)]
          nil -> []
        end
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if comment_line?(line) do
        line
      else
        Regex.replace(@pattern, line, fn _match, identifier, space ->
          "#{identifier}:#{space}"
        end)
      end
    end)
  end

  defp comment_line?(line), do: Regex.match?(~r/^\s*#/, line)

  defp build_issue(line_no, identifier) do
    %Issue{
      rule: :fix_keyword_list_colon_syntax,
      message:
        "LLM colon-on-wrong-side keyword `:#{identifier}:` should be `#{identifier}:`.",
      meta: %{line: line_no}
    }
  end
end
