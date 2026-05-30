defmodule Credence.Pattern.NoRedundantSortComparator do
  @moduledoc """
  Readability rule (check-only): Detects `Enum.sort/2` with a comparator that
  manually reimplements lexicographic ordering on destructured list or tuple
  elements.

  Elixir's `Enum.sort/1` already compares lists and tuples element by element,
  so a comparator like:

      Enum.sort(coords, fn [a, b], [c, d] -> a < c or (a == c and b < d) end)

  can be simplified to `Enum.sort(coords)` when all elements are distinct
  (e.g. coordinate pairs from a MapSet). For potentially duplicate elements,
  only the `<=` variant is strictly equivalent to `Enum.sort/1`.

  ## Flagged

      Enum.sort(coords, fn [r1, c1], [r2, c2] -> r1 < r2 or (r1 == r2 and c1 < c2) end)
      Enum.sort(pairs, fn [a, b], [c, d] -> a <= c or (a == c and b <= d) end)

  ## Not flagged

      Enum.sort(coords)                                        # already default
      Enum.sort(coords, fn a, b -> a < b end)                  # no destructuring
      Enum.sort(coords, fn [a, b], [c, d] -> a > c or ... end) # descending
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, issues ->
          if redundant_comparator_in_sort?(node) do
            {node, [build_issue(meta_of(node)) | issues]}
          else
            {node, issues}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp redundant_comparator_in_sort?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, [_collection, comparator]}
       ) do
    redundant_comparator?(comparator)
  end

  defp redundant_comparator_in_sort?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, [comparator]}
       ) do
    redundant_comparator?(comparator)
  end

  defp redundant_comparator_in_sort?(_), do: false

  defp redundant_comparator?({:fn, _, [{:->, _, [params, body]}]})
       when length(params) == 2 do
    case params do
      [pat1, pat2] ->
        case {extract_pattern_elements(pat1), extract_pattern_elements(pat2)} do
          {{vars1, shape}, {vars2, shape}} when shape != :unknown and length(vars1) >= 2 ->
            ascending_lexicographic_body?(body, vars1, vars2)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp redundant_comparator?(_), do: false

  defp extract_pattern_elements({:__block__, _, [inner]}) do
    # Sourceror wraps list/tuple patterns in a block node
    extract_pattern_elements(inner)
  end

  defp extract_pattern_elements(list) when is_list(list) do
    vars =
      Enum.reduce_while(list, [], fn
        {name, _, ctx}, acc when is_atom(name) and is_atom(ctx) -> {:cont, [name | acc]}
        _, _ -> {:halt, :error}
      end)

    case vars do
      :error -> {[], :unknown}
      names -> {Enum.reverse(names), :list}
    end
  end

  defp extract_pattern_elements({:{}, _, elements}) do
    vars =
      Enum.reduce_while(elements, [], fn
        {name, _, ctx}, acc when is_atom(name) and is_atom(ctx) -> {:cont, [name | acc]}
        _, _ -> {:halt, :error}
      end)

    case vars do
      :error -> {[], :unknown}
      names -> {Enum.reverse(names), :tuple}
    end
  end

  defp extract_pattern_elements({{_, _, _} = v1, {_, _, _} = v2}) do
    extract_pattern_elements({:{}, [], [v1, v2]})
  end

  defp extract_pattern_elements(_), do: {[], :unknown}

  defp ascending_lexicographic_body?(body, [v1 | rest1], [v2 | rest2]) do
    case body do
      {op, _, [{va, _, _}, {vb, _, _}]}
      when (op == :< or op == :<=) and va == v1 and vb == v2 and rest1 == [] and rest2 == [] ->
        # Single element comparison: a < c or a <= c
        true

      {:or, _, [left, right]} ->
        ascending_lexicographic_or?(left, right, [v1 | rest1], [v2 | rest2])

      {:"||", _, [left, right]} ->
        ascending_lexicographic_or?(left, right, [v1 | rest1], [v2 | rest2])

      _ ->
        false
    end
  end

  defp ascending_lexicographic_body?(_, _, _), do: false

  defp ascending_lexicographic_or?(left, right, [v1 | rest1], [v2 | rest2]) do
    case left do
      {op, _, [{va, _, _}, {vb, _, _}]} when (op == :< or op == :<=) and va == v1 and vb == v2 ->
        # First comparison matches: v1 < v2 or (v1 == v2 and ...)
        case right do
          {:and, _, [eq_check, deeper]}
          when rest1 != [] and rest2 != [] ->
            ascending_lexicographic_eq_and_deeper?(eq_check, deeper, v1, v2, rest1, rest2)

          {:"&&", _, [eq_check, deeper]}
          when rest1 != [] and rest2 != [] ->
            ascending_lexicographic_eq_and_deeper?(eq_check, deeper, v1, v2, rest1, rest2)

          # Two-element terminal: v1 < v2 or (v1 == v2 and v1b < v2b)
          {:and, _, [eq_check, {op2, _, [{vb, _, _}, {vd, _, _}]}]}
          when rest1 == [hd(rest1)] and rest2 == [hd(rest2)] and
                 (op2 == :< or op2 == :<=) and vb == hd(rest1) and vd == hd(rest2) ->
            equality_check?(eq_check, v1, v2)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp ascending_lexicographic_or?(_, _, _, _), do: false

  defp ascending_lexicographic_eq_and_deeper?(eq_check, deeper, v1, v2, rest1, rest2) do
    case eq_check do
      {:==, _, [{va, _, _}, {vb, _, _}]} when va == v1 and vb == v2 ->
        ascending_lexicographic_body?(deeper, rest1, rest2)

      _ ->
        false
    end
  end

  defp equality_check?({:==, _, [{va, _, _}, {vb, _, _}]}, expected_a, expected_b)
       when va == expected_a and vb == expected_b,
       do: true

  defp equality_check?(_, _, _), do: false

  defp meta_of({{:., _, _}, meta, _}), do: meta
  defp meta_of(_), do: []

  defp build_issue(meta) do
    %Issue{
      rule: :no_redundant_sort_comparator,
      message:
        "Sort comparator reimplements default lexicographic ordering. " <>
          "Use `Enum.sort/1` instead — Elixir already compares lists and tuples element by element.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
