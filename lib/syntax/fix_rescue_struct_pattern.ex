defmodule Credence.Syntax.FixRescueStructPattern do
  @moduledoc """
  Fixes `%ExceptionType -> body` inside rescue clauses (Python `except` syntax).

  LLMs sometimes produce `%FunctionClauseError -> body` inside a `rescue`
  block, carrying over Python's `except ExceptionType as e` idiom. In Elixir
  this is a syntax error — `%` starts a map/struct literal, not a pattern
  match on an exception type.

  The fix rewrites `%ExceptionType ->` to `e in ExceptionType ->`, which is
  the valid Elixir rescue-clause binding syntax.

  ## Bad (won't parse)

      rescue
        %FunctionClauseError -> {:error, :function_clause}
        %ArgumentError -> {:error, :argument}
      end

  ## Good

      rescue
        e in FunctionClauseError -> {:error, :function_clause}
        e in ArgumentError -> {:error, :argument}
      end
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches `%ModuleName ->` where ModuleName is a bare identifier (no braces).
  # This is the Python-style `%ExceptionType ->` that doesn't parse in Elixir.
  # Safe against maps (%{...}) and structs (%Mod{...}) because those have `{`
  # immediately after `%` or the module name, which the `\s*->` tail rejects.
  @bad_pattern ~r/%([A-Za-z_]\w*)\s*->/
  @check_pattern ~r/%[A-Za-z_]\w*\s*->/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@check_pattern, line) do
        [%Issue{rule: :fix_rescue_struct_pattern,
                message: "Python-style `%ExceptionType ->` is not valid Elixir. " <>
                         "Use `e in ExceptionType ->` instead.",
                meta: %{line: line_no}}]
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
      Regex.replace(@bad_pattern, line, "e in \\1 ->")
    end)
  end
end
