defmodule Credence.Pattern.NoSortWithKeyComparator do
  @moduledoc """
  Detects `Enum.sort/2` with a single-key comparator on tuples and
  rewrites it to the more idiomatic `Enum.sort_by/2`.

  When sorting a list of tuples by a single extracted field, prefer
  `Enum.sort_by/2` which is more concise:

      # Flagged
      Enum.sort(list, fn {_, _, w1}, {_, _, w2} -> w1 < w2 end)

      # Preferred
      Enum.sort_by(list, &elem(&1, 2))

  Both ascending (`<`, `<=`) and descending (`>`, `>=`) comparators are
  detected.  Descending comparators produce `Enum.sort_by/3` with `:desc`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, issues ->
          case detect(node) do
            {:ok, pos, _dir} ->
              issue = %Issue{
                rule: :no_sort_with_key_comparator,
                message:
                  "Enum.sort/2 with a single-key tuple comparator. " <>
                    "Prefer Enum.sort_by/2, e.g. Enum.sort_by(list, &elem(&1, #{pos})).",
                meta: %{line: line_of(node)}
              }

              {node, [issue | issues]}

            :error ->
              {node, issues}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    RuleHelpers.patches_from_ast_transform(ast, source, &transform_ast/1)
  end

  # ── Detection ──────────────────────────────────────────────────

  # Non-pipe: Enum.sort(collection, comparator)
  defp detect(
         {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, [_collection, comparator]}
       ) do
    extract_key_comparator(comparator)
  end

  # Pipe: collection |> Enum.sort(comparator)
  defp detect(
         {:|>, _,
          [
            _collection,
            {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, [comparator]}
          ]}
       ) do
    extract_key_comparator(comparator)
  end

  defp detect(_), do: :error

  # ── Transform ──────────────────────────────────────────────────

  defp transform_ast(ast), do: transform_node(ast)

  # Non-pipe: Enum.sort(collection, comparator) → Enum.sort_by(...)
  defp transform_node(
         {{:., meta, [{:__aliases__, ameta, [:Enum]}, :sort]}, call_meta,
          [collection, comparator]}
       ) do
    case extract_key_comparator(comparator) do
      {:ok, pos, :asc} ->
        {{:., meta, [{:__aliases__, ameta, [:Enum]}, :sort_by]}, call_meta,
         [transform_node(collection), capture_elem(pos)]}

      {:ok, pos, :desc} ->
        {{:., meta, [{:__aliases__, ameta, [:Enum]}, :sort_by]}, call_meta,
         [transform_node(collection), capture_elem(pos), :desc]}

      :error ->
        {{:., meta, [{:__aliases__, ameta, [:Enum]}, :sort]}, call_meta,
         [transform_node(collection), transform_node(comparator)]}
    end
  end

  # Pipe: collection |> Enum.sort(comparator) → collection |> Enum.sort_by(...)
  defp transform_node(
         {:|>, pipe_meta,
          [
            collection,
            {{:., meta, [{:__aliases__, ameta, [:Enum]}, :sort]}, call_meta, [comparator]}
          ]}
       ) do
    case extract_key_comparator(comparator) do
      {:ok, pos, :asc} ->
        {:|>, pipe_meta,
         [
           transform_node(collection),
           {{:., meta, [{:__aliases__, ameta, [:Enum]}, :sort_by]}, call_meta,
            [capture_elem(pos)]}
         ]}

      {:ok, pos, :desc} ->
        {:|>, pipe_meta,
         [
           transform_node(collection),
           {{:., meta, [{:__aliases__, ameta, [:Enum]}, :sort_by]}, call_meta,
            [capture_elem(pos), :desc]}
         ]}

      :error ->
        {:|>, pipe_meta,
         [
           transform_node(collection),
           {{:., meta, [{:__aliases__, ameta, [:Enum]}, :sort]}, call_meta,
            [transform_node(comparator)]}
         ]}
    end
  end

  # 2-tuple
  defp transform_node({left, right}), do: {transform_node(left), transform_node(right)}

  # Generic 3-tuple AST node with list arguments
  defp transform_node({_, _, args} = node) when is_list(args) do
    {form, meta, _} = node
    {transform_node(form), meta, Enum.map(args, &transform_node/1)}
  end

  # List of AST nodes
  defp transform_node(list) when is_list(list), do: Enum.map(list, &transform_node/1)

  # Leaf node
  defp transform_node(node), do: node

  # ── Helpers ────────────────────────────────────────────────────

  defp extract_key_comparator({:fn, _, [{:->, _, [[pat1, pat2], body]}]}) do
    with {:ok, {pos, size, var1}} <- extract_tuple_key(pat1),
         {:ok, {pos2, size2, var2}} <- extract_tuple_key(pat2),
         true <- pos == pos2 and size == size2,
         {:ok, op} <- simple_comparison(body, var1, var2) do
      direction = if op in [:<, :<=], do: :asc, else: :desc
      {:ok, pos, direction}
    else
      _ -> :error
    end
  end

  defp extract_key_comparator(_), do: :error

  defp extract_tuple_key({:__block__, _, [inner]}), do: extract_tuple_key(inner)
  defp extract_tuple_key({:{}, _, elements}), do: find_single_var(elements)
  defp extract_tuple_key({{_, _, _} = v1, {_, _, _} = v2}), do: find_single_var([v1, v2])
  defp extract_tuple_key(_), do: :error

  defp find_single_var(elements) do
    indexed = Enum.with_index(elements)
    vars = Enum.filter(indexed, fn {elem, _} -> variable?(elem) end)
    wildcard_count = Enum.count(elements, &wildcard?/1)
    size = length(elements)

    case vars do
      [{var, pos}] when wildcard_count == size - 1 ->
        {:ok, {pos, size, var_name(var)}}

      _ ->
        :error
    end
  end

  defp variable?({name, _, ctx}) when is_atom(name) and is_atom(ctx) and name != :_, do: true
  defp variable?(_), do: false

  defp wildcard?({:_, _, _}), do: true
  defp wildcard?(_), do: false

  defp var_name({name, _, _}), do: name

  defp simple_comparison(body, var1, var2) do
    case unwrap_block(body) do
      {op, _, [{v1, _, _}, {v2, _, _}]}
      when op in [:<, :<=, :>, :>=] and v1 == var1 and v2 == var2 ->
        {:ok, op}

      _ ->
        :error
    end
  end

  defp unwrap_block({:__block__, _, [inner]}), do: inner
  defp unwrap_block(body), do: body

  # Generate &elem(&1, pos) AST by parsing a string — Sourceror's metadata
  # requirements are tricky to produce by hand.
  defp capture_elem(pos) do
    src = "&elem(&1, #{pos})"
    Sourceror.parse_string!(src)
  end

  defp line_of({{:., _, _}, meta, _}), do: Keyword.get(meta, :line)
  defp line_of({:|>, meta, _}), do: Keyword.get(meta, :line)
  defp line_of(_), do: nil
end
