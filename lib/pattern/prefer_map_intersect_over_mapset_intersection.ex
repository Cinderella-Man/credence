defmodule Credence.Pattern.PreferMapIntersectOverMapsetIntersection do
  @moduledoc """
  Detects MapSet-based intersection of map keys that can be replaced with
  `Map.intersect/3` (Elixir 1.14+).

  The verbose pipeline `Map.keys(a) |> MapSet.new() |> MapSet.intersection(MapSet.new(Map.keys(b))) |> MapSet.to_list()`
  followed by an `Enum.map` that fetches and merges values from both maps
  can be replaced with a single `Map.intersect/3` call.

  ## Bad

      common_keys =
        Map.keys(freq1)
        |> MapSet.new()
        |> MapSet.intersection(MapSet.new(Map.keys(freq2)))
        |> MapSet.to_list()

      common_keys
      |> Enum.map(fn element ->
        count1 = Map.fetch!(freq1, element)
        count2 = Map.fetch!(freq2, element)
        {element, min(count1, count2)}
      end)
      |> Enum.sort()

  ## Good

      freq1
      |> Map.intersect(freq2, fn _key, count1, count2 -> min(count1, count2) end)
      |> Enum.sort_by(fn {key, _value} -> key end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        if mapset_intersection_pipeline?(node) do
          meta = elem(node, 1)

          issue = %Issue{
            rule: :prefer_map_intersect_over_mapset_intersection,
            message: "Use `Map.intersect/3` instead of MapSet intersection pipeline on map keys.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | acc]}
        else
          {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      Macro.postwalk(input, fn
        {:__block__, meta, exprs} when is_list(exprs) ->
          case transform_block(exprs) do
            {:ok, new_exprs} -> {:__block__, meta, new_exprs}
            :error -> {:__block__, meta, exprs}
          end

        node ->
          node
      end)
    end)
  end

  # ── detection helpers ──────────────────────────────────────────────

  defp mapset_intersection_pipeline?(node) do
    match?(
      {:|>, _,
       [
         {:|>, _,
          [
            {:|>, _,
             [
               {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [_]},
               {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []}
             ]},
            {{:., _, [{:__aliases__, _, [:MapSet]}, :intersection]}, _, [_]}
          ]},
         {{:., _, [{:__aliases__, _, [:MapSet]}, :to_list]}, _, []}
       ]},
      node
    )
  end

  # ── block transformation ──────────────────────────────────────────

  defp transform_block(exprs) do
    with {:ok, assign_idx, var_name, freq1_ast, freq2_ast} <-
           find_mapset_assignment(exprs),
         {:ok, map_idx, count1, count2, merge_expr} <-
           find_enum_map(exprs, assign_idx + 1, var_name, freq1_ast, freq2_ast) do
      replacement = build_map_intersect(freq1_ast, freq2_ast, {count1, count2, merge_expr})

      new_exprs =
        exprs
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {_, ^assign_idx} -> []
          {_, ^map_idx} -> [replacement]
          {expr, _} -> [expr]
        end)

      {:ok, new_exprs}
    end
  end

  # Find assignment: var_name = Map.keys(a) |> MapSet.new() |> ...
  defp find_mapset_assignment(exprs) do
    exprs
    |> Enum.with_index()
    |> Enum.find_value(:error, fn
      {{:=, _, [{var_name, _, nil}, pipeline]}, idx} ->
        case extract_mapset_pipeline_vars(pipeline) do
          {:ok, freq1, freq2} -> {:ok, idx, var_name, freq1, freq2}
          :error -> nil
        end

      _ ->
        nil
    end)
  end

  defp extract_mapset_pipeline_vars(node) do
    case node do
      {:|>, _,
       [
         {:|>, _,
          [
            {:|>, _,
             [
               {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [freq1]},
               {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []}
             ]},
            {{:., _, [{:__aliases__, _, [:MapSet]}, :intersection]}, _,
             [
               {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _,
                [
                  {{:., _, [{:__aliases__, _, [:Map]}, :keys]}, _, [freq2]}
                ]}
             ]}
          ]},
         {{:., _, [{:__aliases__, _, [:MapSet]}, :to_list]}, _, []}
       ]} ->
        {:ok, freq1, freq2}

      _ ->
        :error
    end
  end

  # Find Enum.map(var, fn ...) |> Enum.sort() using the assigned variable
  defp find_enum_map(exprs, start_idx, var_name, freq1_ast, freq2_ast) do
    freq1_name = elem(freq1_ast, 0)
    freq2_name = elem(freq2_ast, 0)

    exprs
    |> Enum.drop(start_idx)
    |> Enum.with_index(start_idx)
    |> Enum.find_value(:error, fn {expr, idx} ->
      case extract_enum_map_merge(expr, var_name, freq1_name, freq2_name) do
        {:ok, result} -> {:ok, idx, elem(result, 0), elem(result, 1), elem(result, 2)}
        :error -> nil
      end
    end)
  end

  defp extract_enum_map_merge(expr, var_name, freq1_name, freq2_name) do
    case expr do
      {:|>, _,
       [
         {:|>, _,
          [
            {^var_name, _, nil},
            {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [fn_expr]}
          ]},
         {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, []}
       ]} ->
        extract_merge_fn(fn_expr, freq1_name, freq2_name)

      _ ->
        :error
    end
  end

  defp extract_merge_fn(fn_expr, freq1_name, freq2_name) do
    case fn_expr do
      {:fn, _,
       [
         {:->, _,
          [
            [{elem_var, _, nil}],
            {:__block__, _, stmts}
          ]}
       ]} ->
        match_merge_stmts(stmts, elem_var, freq1_name, freq2_name)

      _ ->
        :error
    end
  end

  defp match_merge_stmts(stmts, elem_var, freq1_name, freq2_name) do
    case stmts do
      [
        {:=, _,
         [
           {count1, _, nil},
           {{:., _, [{:__aliases__, _, [:Map]}, :fetch!]}, _,
            [{^freq1_name, _, nil}, {^elem_var, _, nil}]}
         ]},
        {:=, _,
         [
           {count2, _, nil},
           {{:., _, [{:__aliases__, _, [:Map]}, :fetch!]}, _,
            [{^freq2_name, _, nil}, {^elem_var, _, nil}]}
         ]},
        {:__block__, _, [{{^elem_var, _, nil}, merge_expr}]}
      ] ->
        {:ok, {count1, count2, merge_expr}}

      _ ->
        :error
    end
  end

  # ── build replacement AST ─────────────────────────────────────────

  defp build_map_intersect(freq1_ast, freq2_ast, {count1, count2, merge_expr}) do
    # fn _key, count1, count2 -> merge_expr end
    intersect_fn =
      {:fn, [],
       [
         {:->, [],
          [
            [{:_key, [], nil}, {count1, [], nil}, {count2, [], nil}],
            merge_expr
          ]}
       ]}

    # fn {key, _value} -> key end
    sort_by_fn =
      {:fn, [],
       [
         {:->, [],
          [
            [{:__block__, [], [{{:key, [], nil}, {:_value, [], nil}}]}],
            {:key, [], nil}
          ]}
       ]}

    # freq1 |> Map.intersect(freq2, intersect_fn) |> Enum.sort_by(sort_by_fn)
    freq1_ast
    |> pipe({{:., [], [{:__aliases__, [], [:Map]}, :intersect]}, [], [freq2_ast, intersect_fn]})
    |> pipe({{:., [], [{:__aliases__, [], [:Enum]}, :sort_by]}, [], [sort_by_fn]})
  end

  defp pipe(left, right), do: {:|>, [], [left, right]}
end
