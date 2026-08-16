defmodule Credence.Semantic.FixHallucinatedEnumRange do
  @moduledoc """
  Fixes the compile warning for calls to the hallucinated `Enum.range/2`.

  `Enum.range/2` does not exist in Elixir — it is a common LLM hallucination
  of the range literal. Because the `Enum` module itself exists, the compiler
  emits a warning whose position points at the function name:

      "Enum.range/2 is undefined or private"

  The fix replaces the flagged `Enum.range(a, b)` call with the idiomatic
  range literal `a..b`, spliced in via a Sourceror patch anchored at the
  diagnostic's line/column — only the flagged call changes, every other line
  survives byte-for-byte. Compound arguments keep their precedence: the
  rendered literal parenthesizes them (`0..(length(list) - 1)`).

  Only messages that start with `Enum.range/2 is undefined or private` are
  claimed: a user module whose path merely ends in `Enum`
  (`MyEnum.range/2 …`) and other arities (`Enum.range/3`) stay with the
  generic `UndefinedFunction` rule. Shapes that emit the same message but
  admit no in-place literal rewrite — `&Enum.range/2` captures, the piped
  `x |> Enum.range(y)`, `Elixir.Enum.range(a, b)`, and an `Enum.range(a, b)`
  spelling that resolves to another module through `alias …, as: Enum` — are
  deliberately left unfixed: the anchor only accepts a direct two-argument
  `Enum.range(…)` call whose function name sits exactly at the flagged
  column, and the fix no-ops rather than risk a wrong edit (same policy as
  `FixHallucinatedCalendarIsoAccessor`).

  ## Bad

      defmodule CredenceEnumRangeMultilineE2E do
        def a(n) do
          Enum.range(
            0,
            n
          )
        end
      end

  ## Good

      defmodule CredenceEnumRangeMultilineE2E do
        def a(n) do
          0..n
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @message_prefix "Enum.range/2 is undefined or private"

  # `Enum.` — the diagnostic column points at `range`, five characters after
  # the start of the qualified call.
  @prefix_width 5

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @message_prefix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_enum_range,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, node, range} <- flagged_call(ast, position(diagnostic)) do
      {_, _, [first, last]} = node
      change = Sourceror.to_string({:.., [], [first, last]})
      Sourceror.patch_string(source, [%{range: range, change: change}])
    else
      _ -> source
    end
  end

  # The flagged call is the candidate whose function name sits exactly at the
  # diagnostic column. Without a column, a lone candidate on the flagged line
  # is unambiguous; anything else no-ops rather than guess.
  defp flagged_call(ast, {line_no, col}) do
    candidates = candidates_on_line(ast, line_no)

    if is_integer(col) do
      case Enum.filter(candidates, fn {_, range} ->
             range.start[:column] + @prefix_width == col
           end) do
        [{node, range}] -> {:ok, node, range}
        _ -> :error
      end
    else
      case candidates do
        [{node, range}] -> {:ok, node, range}
        _ -> :error
      end
    end
  end

  # A candidate is a direct `Enum.range(a, b)` call — exact `[:Enum]` alias,
  # exactly two arguments — starting on the flagged line. The capture
  # (`&Enum.range/2`, zero args in the dot call) and piped (`x |> Enum.range(y)`,
  # one arg) forms never qualify.
  defp candidates_on_line(ast, line_no) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :range]}, _, [_, _]} = node, acc ->
          case Sourceror.get_range(node) do
            %{start: start} = range ->
              if start[:line] == line_no, do: {node, [{node, range} | acc]}, else: {node, acc}

            nil ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp position(%{position: {line, col}}) when is_integer(line), do: {line, col}
  defp position(%{position: line}) when is_integer(line), do: {line, nil}
  defp position(_), do: {nil, nil}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
