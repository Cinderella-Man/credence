defmodule Credence.Semantic.FixHallucinatedMapPutArity do
  @moduledoc """
  Fixes the compile warning for calls to `Map.put` with a hallucinated arity.

  Only `Map.put/3` exists. Two LLM hallucination shapes are repaired:

  1. **`Map.put/5`, `/7`, … (odd arity ≥ 5)** — Python-dict style multi-key
     construction. Pairs chain into nested `Map.put/3` calls, preserving
     argument order (and thus side-effect order):

         # Wrong (hallucinated):
         Map.put(%{}, :type, :missing_required, :path, [:a])

         # Correct (chained Map.put/3):
         Map.put(Map.put(%{}, :type, :missing_required), :path, [:a])

  2. **`Map.put/2` with a map-literal second argument** — Python's
     `dict.update`. The intent is a merge:

         # Wrong (hallucinated):
         Map.put(state, %{status: :suspended, reason: "payment_failed"})

         # Correct (Map.merge/2):
         Map.merge(state, %{status: :suspended, reason: "payment_failed"})

  The rewrite is spliced in via a Sourceror patch anchored at the diagnostic's
  line/column — only the flagged call changes, every other line survives
  byte-for-byte.

  Only messages that start with `Map.put/<arity> is undefined or private` for
  a repairable arity (2, or odd ≥ 5) are claimed: a user module whose path
  merely ends in `Map` (`MyApp.Map.put/5 …`) and other arities (`Map.put/4`,
  `/6` — a dangling key with no value, no unambiguous repair) stay with the
  generic `UndefinedFunction` rule. Shapes that emit the same message but
  admit no in-place rewrite — `&Map.put/5` captures, the piped
  `x |> Map.put(:a, 1, :b, 2)`, `Elixir.Map.put(…)`, a spelling that resolves
  to another module through `alias …, as: Map`, and a two-argument call whose
  second argument is not a map literal — are deliberately left unfixed: the
  anchor only accepts a direct call with exactly the flagged argument count
  sitting exactly at the flagged column, and the fix no-ops rather than risk
  a wrong edit (same policy as `FixHallucinatedEnumRange`). The
  `should_report?/2` phase hook keeps `analyze` honest by reporting an issue
  only when `fix/2` would actually rewrite the source.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @message_re ~r|^Map\.put/(\d+) is undefined or private|

  # `Map.` — the diagnostic column points at `put`, four characters after
  # the start of the qualified call.
  @prefix_width 4

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    claimed_arity(msg) != nil
  end

  def match?(_), do: false

  @doc """
  Phase hook (`Credence.Semantic.match_rules/2`): report an issue only when
  `fix/2` would actually rewrite the source. The same message is also emitted
  for captures, piped calls, alias-shadowed modules, and `Map.put/2` with a
  non-map second argument, which this rule deliberately does not rewrite.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_hallucinated_map_put_arity,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg} = diagnostic) do
    with arity when arity != nil <- claimed_arity(msg),
         {:ok, ast} <- Sourceror.parse_string(source),
         {:ok, node, range} <- flagged_call(ast, arity, position(diagnostic)) do
      change = node |> rewrite(arity) |> Sourceror.to_string()
      Sourceror.patch_string(source, [%{range: range, change: change}])
    else
      _ -> source
    end
  end

  # A repairable arity: 2 (map-literal merge) or odd ≥ 5 (pair chaining).
  defp claimed_arity(msg) do
    with [_, arity] <- Regex.run(@message_re, msg),
         arity = String.to_integer(arity),
         true <- arity == 2 or (arity >= 5 and rem(arity, 2) == 1) do
      arity
    else
      _ -> nil
    end
  end

  # Map.put(base, %{…}) → Map.merge(base, %{…})
  defp rewrite({_, _, [base, map_literal]}, 2) do
    {{:., [], [{:__aliases__, [], [:Map]}, :merge]}, [], [base, map_literal]}
  end

  # Map.put(map, k1, v1, k2, v2, …) → Map.put(Map.put(map, k1, v1), k2, v2)…
  # Fresh meta on the built calls so the printer renders them inline; the
  # original argument nodes are reused once each, in source order.
  defp rewrite({_, _, [map | rest]}, _arity) do
    rest
    |> Enum.chunk_every(2)
    |> Enum.reduce(map, fn [key, value], acc ->
      {{:., [], [{:__aliases__, [], [:Map]}, :put]}, [], [acc, key, value]}
    end)
  end

  # The flagged call is the candidate whose function name sits exactly at the
  # diagnostic column. Without a column, a lone candidate on the flagged line
  # is unambiguous; anything else no-ops rather than guess.
  defp flagged_call(ast, arity, {line_no, col}) do
    candidates = candidates_on_line(ast, arity, line_no)

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

  # A candidate is a direct `Map.put(…)` call — exact `[:Map]` alias, exactly
  # the flagged argument count, and for arity 2 a map-literal second argument —
  # starting on the flagged line. The capture (`&Map.put/5`, zero args in the
  # dot call) and piped (`x |> Map.put(…)`, one fewer arg) forms never qualify.
  defp candidates_on_line(ast, arity, line_no) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Map]}, :put]}, _, args} = node, acc
        when is_list(args) ->
          if length(args) == arity and repairable_args?(args, arity) do
            case Sourceror.get_range(node) do
              %{start: start} = range ->
                if start[:line] == line_no, do: {node, [{node, range} | acc]}, else: {node, acc}

              nil ->
                {node, acc}
            end
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp repairable_args?([_base, {:%{}, _, _}], 2), do: true
  defp repairable_args?(_, 2), do: false
  defp repairable_args?(_, _), do: true

  defp position(%{position: {line, col}}) when is_integer(line), do: {line, col}
  defp position(%{position: line}) when is_integer(line), do: {line, nil}
  defp position(_), do: {nil, nil}

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
