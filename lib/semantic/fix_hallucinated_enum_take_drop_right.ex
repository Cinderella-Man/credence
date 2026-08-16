defmodule Credence.Semantic.FixHallucinatedEnumTakeDropRight do
  @moduledoc """
  Fixes the compile warning for calls to the hallucinated `Enum.take_right/2`
  and `Enum.drop_right/2`.

  Neither function exists in Elixir — they are common LLM hallucinations of
  `Enum.take/2` / `Enum.drop/2` with a negative count. Because the `Enum`
  module itself exists, the compiler emits a warning whose position points at
  the function name:

      "Enum.take_right/2 is undefined or private"
      "Enum.drop_right/2 is undefined or private"

  The fix replaces the flagged `Enum.take_right(list, n)` with
  `Enum.take(list, -n)` (and `drop_right` with `Enum.drop(list, -n)`),
  spliced in via a Sourceror patch anchored at the diagnostic's line/column —
  only the flagged call changes, every other line survives byte-for-byte.
  A literal count folds into a signed literal (`2` → `-2`, `-2` → `2`), an
  already-negated count cancels (`-n` → `n`), and a compound count keeps its
  precedence via parentheses (`n + 1` → `-(n + 1)`).

  Only messages that start with `Enum.take_right/2 is undefined or private`
  (or the `drop_right` twin) are claimed: a user module whose path merely
  ends in `Enum` (`MyEnum.take_right/2 …`) and other arities stay with the
  generic `UndefinedFunction` rule. Shapes that emit the same message but
  admit no in-place rewrite — `&Enum.take_right/2` captures, the piped
  `x |> Enum.take_right(n)`, `Elixir.Enum.take_right(a, b)`, and a spelling
  that resolves to another module through `alias …, as: Enum` — are
  deliberately left unfixed: the anchor only accepts a direct two-argument
  call of the function the message names, sitting exactly at the flagged
  column, and the fix no-ops rather than risk a wrong edit (same policy as
  `FixHallucinatedEnumRange`).

  ## Bad

      defmodule CredenceTakeRightMultilineE2E do
        def a(list, n) do
          Enum.take_right(
            list,
            n
          )
        end
      end

  ## Good

      defmodule CredenceTakeRightMultilineE2E do
        def a(list, n) do
          Enum.take(list, -n)
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @replacements %{take_right: :take, drop_right: :drop}

  # `Enum.` — the diagnostic column points at the function name, five
  # characters after the start of the qualified call.
  @prefix_width 5

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    target_fn(msg) != nil
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_enum_take_drop_right,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg} = diagnostic) do
    with fn_name when fn_name != nil <- target_fn(msg),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, node, range} <- flagged_call(ast, fn_name, position(diagnostic)) do
      {_, _, [enumerable, count]} = node

      replacement =
        {{:., [], [{:__aliases__, [], [:Enum]}, Map.fetch!(@replacements, fn_name)]}, [],
         [enumerable, negate(count)]}

      change = Sourceror.to_string(replacement)
      Sourceror.patch_string(source, [%{range: range, change: change}])
    else
      _ -> source
    end
  end

  defp target_fn(msg) do
    cond do
      String.starts_with?(msg, "Enum.take_right/2 is undefined or private") -> :take_right
      String.starts_with?(msg, "Enum.drop_right/2 is undefined or private") -> :drop_right
      true -> nil
    end
  end

  # "n from the end" is `-n`: a literal count becomes a signed literal, an
  # already-negated count cancels, anything else is wrapped in a unary minus
  # (Sourceror parenthesizes compound operands). Fresh meta throughout so the
  # printer renders the value, not a stale source token.
  defp negate({:__block__, _, [n]}) when is_integer(n), do: {:__block__, [], [-n]}
  defp negate({:-, _, [inner]}), do: inner
  defp negate(node), do: {:-, [], [node]}

  # The flagged call is the candidate whose function name sits exactly at the
  # diagnostic column. Without a column, a lone candidate on the flagged line
  # is unambiguous; anything else no-ops rather than guess.
  defp flagged_call(ast, fn_name, {line_no, col}) do
    candidates = candidates_on_line(ast, fn_name, line_no)

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

  # A candidate is a direct call of the function the message names — exact
  # `[:Enum]` alias, exactly two arguments — starting on the flagged line.
  # The capture (`&Enum.take_right/2`, zero args in the dot call) and piped
  # (`x |> Enum.take_right(n)`, one arg) forms never qualify.
  defp candidates_on_line(ast, fn_name, line_no) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, ^fn_name]}, _, [_, _]} = node, acc ->
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
