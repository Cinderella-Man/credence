defmodule Credence.Syntax.FixEtsOptionsBareKeypos do
  @moduledoc """
  Fixes bare `:keypos, N` atoms in `:ets.new/2` options lists.

  LLMs write `:keypos, 1` as two separate atoms in `:ets.new/2` options instead
  of the required tuple `{:keypos, 1}`; this causes a runtime ArgumentError on
  every call.

  ## Bad (causes ArgumentError)

      :ets.new(:my_table, [:named_table, :set, :public, :keypos, 1])

  ## Good

      :ets.new(:my_table, [:named_table, :set, :public, {:keypos, 1}])
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Matches bare `:keypos,` followed by a digit, but NOT inside a tuple `{:keypos, ...}`.
  # Group 1: the integer value (e.g. `1`)
  @pattern ~r/(?<!\{):keypos\s*,\s*(\d+)/

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
          [_match, _num] -> [build_issue(line_no)]
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
        Regex.replace(@pattern, line, fn _match, num ->
          "{:keypos, #{num}}"
        end)
      end
    end)
  end

  defp comment_line?(line), do: Regex.match?(~r/^\s*#/, line)

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_ets_options_bare_keypos,
      message:
        "Bare `:keypos, N` in :ets.new/2 options must be a tuple `{:keypos, N}`. " <>
          "Separate atoms cause a runtime ArgumentError.",
      meta: %{line: line_no}
    }
  end
end
