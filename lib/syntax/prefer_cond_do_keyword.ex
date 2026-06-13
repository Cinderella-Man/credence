defmodule Credence.Syntax.PreferCondDoKeyword do
  @moduledoc """
  Detects and fixes `cond ->` (missing `do` keyword) syntax errors.

  LLMs occasionally generate `cond ->` instead of `cond do`, mixing
  Rust/OCaml match-arm syntax into Elixir. The parser fails at `->`
  without the `do` keyword. Replacing `cond ->` with `cond do` resolves
  the parse error with zero behaviour change.

  ## Bad (won't parse)

      cond ->
        list == [] -> nil
        true -> Enum.min(list)
      end

  ## Good

      cond do
        list == [] -> nil
        true -> Enum.min(list)
      end
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches `cond` followed by whitespace then `->` (the broken pattern)
  @bad_pattern ~r/\bcond\s+->/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@bad_pattern, line) do
        [%Issue{rule: :prefer_cond_do_keyword, message: "cond -> should be cond do", meta: %{line: line_no}}]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    String.replace(source, @bad_pattern, "cond do")
  end
end
