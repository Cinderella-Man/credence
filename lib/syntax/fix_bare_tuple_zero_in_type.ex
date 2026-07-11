defmodule Credence.Syntax.FixBareTupleZeroInType do
  @moduledoc """
  Fixes bare `()` before `->` in `@type` declarations.

  LLMs frequently emit `@type f :: () -> any()` which fails to parse — bare `()`
  is ambiguous before `->`. Wrapping in parens `(() -> any())` repairs it.

  ## Bad (fails to parse)

      @type task_func :: () -> any()

  ## Good

      @type task_func :: (() -> any())
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Matches `:: () ->` in a @type declaration — bare tuple zero before the arrow.
  # Negative lookbehind excludes already-parenthesized `:: (() ->`.
  @detect_pattern ~r/(?<!\()::\s*\(\)\s*->/

  # Captures the entire function type portion for rewriting:
  # Group 1: everything from `->` to end of type (e.g. `any()` or `(integer()) -> boolean()`)
  @fix_pattern ~r/(?<!\()::\s*(\(\)\s*->.*)/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if comment_line?(line) do
        []
      else
        case Regex.run(@detect_pattern, line) do
          [_match] -> [build_issue(line_no)]
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
        Regex.replace(@fix_pattern, line, fn _match, func_type ->
          ":: (#{func_type})"
        end)
      end
    end)
  end

  defp comment_line?(line), do: Regex.match?(~r/^\s*#/, line)

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_bare_tuple_zero_in_type,
      message:
        "Bare `()` before `->` in @type declaration is ambiguous and fails to parse. " <>
          "Wrap the function type in parens: `(() -> ...)`.",
      meta: %{line: line_no}
    }
  end
end
