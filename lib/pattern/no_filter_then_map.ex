defmodule Credence.Pattern.NoFilterThenMap do
  @moduledoc """
  Detects `Enum.filter/2` piped into `Enum.map/2`, which creates an
  unnecessary intermediate list.

  ## Why this matters

  LLMs produce filter-then-map pipelines that allocate an intermediate
  list from `Enum.filter` only to immediately consume it:

      # Flagged — intermediate list from filter
      numbers
      |> Enum.filter(fn x -> rem(x, 2) == 0 end)
      |> Enum.map(fn x -> x * x end)

      # Better — single pass, no intermediate list
      for x <- numbers, rem(x, 2) == 0, do: x * x

  A `for` comprehension with a guard fuses the filter and transform into
  a single traversal without allocating an intermediate list.

  ## Flagged patterns

  `Enum.filter(predicate)` piped into `Enum.map(transform)`.

  ## Not flagged

  - `Enum.filter(pred)` alone (no following `Enum.map`)
  - `Enum.map(transform)` without preceding `Enum.filter`
  - `Enum.filter |> Enum.map` where filter has no predicate (identity filter)
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, {issues, _seen}} =
      Macro.prewalk(ast, {[], MapSet.new()}, fn node, {issues, seen} ->
        case check_node(node) do
          {:ok, issue} ->
            line = issue.meta.line

            if MapSet.member?(seen, line) do
              {node, {issues, seen}}
            else
              {node, {[issue | issues], MapSet.put(seen, line)}}
            end

          :error ->
            {node, {issues, seen}}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_, patches} =
      Macro.prewalk(ast, [], fn node, patches ->
        case build_patch(node) do
          {:ok, patch} -> {node, [patch | patches]}
          :skip -> {node, patches}
        end
      end)

    patches
  end

  # ── Patch builders ────────────────────────────────────────────────────

  defp build_patch({:|>, _, _} = node) do
    case fix_pipeline(node) do
      nil -> :skip
      {new_ast, original_range} -> emit_patch(original_range, new_ast)
    end
  end

  defp build_patch(_), do: :skip

  defp fix_pipeline({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[first, second], idx} ->
      if filter_step?(first) and map_step?(second) do
        {filter_coll, pred} = extract_filter_parts(first)
        {_map_coll, transform} = extract_map_parts(second)

        {enum, before} = resolve_enum(steps, idx, filter_coll)

        case build_comprehension(enum, pred, transform) do
          {:ok, comprehension} ->
            after_ = Enum.drop(steps, idx + 2)
            pipeline = rebuild_pipeline(before, comprehension, after_)

            if pipeline, do: {pipeline, Sourceror.get_range(node)}

          :error ->
            nil
        end
      end
    end)
  end

  defp resolve_enum(steps, idx, nil) do
    if idx > 0 do
      before = Enum.take(steps, idx)
      enum = Enum.reduce(before, fn s, acc -> {:|>, [], [acc, s]} end)
      {enum, []}
    else
      {nil, []}
    end
  end

  defp resolve_enum(steps, idx, coll) do
    before = Enum.take(steps, idx)

    if before == [] do
      {coll, []}
    else
      {nil, []}
    end
  end

  defp extract_filter_parts({{:., _, [_, :filter]}, _, [pred]}), do: {nil, pred}
  defp extract_filter_parts({{:., _, [_, :filter]}, _, [coll, pred]}), do: {coll, pred}

  defp extract_map_parts({{:., _, [_, :map]}, _, [transform]}), do: {nil, transform}
  defp extract_map_parts({{:., _, [_, :map]}, _, [coll, transform]}), do: {coll, transform}

  defp build_comprehension(nil, _pred, _transform), do: :error

  defp build_comprehension(enum, pred, transform) do
    with {:ok, pred_pattern, pred_body} <- extract_fn(pred),
         {:ok, map_pattern, map_body} <- extract_fn(transform),
         {:ok, merged} <- merge_bindings(pred_pattern, map_pattern) do
      {:ok,
       {:for, [],
        [
          {:<-, [], [merged, enum]},
          pred_body,
          [do: map_body]
        ]}}
    else
      _ -> :error
    end
  end

  defp extract_fn({:fn, _, [{:->, _, [args, body]}]}) do
    case args do
      [pattern] -> {:ok, unwrap_block(pattern), body}
      _ -> :error
    end
  end

  defp extract_fn(_), do: :error

  defp unwrap_block({:__block__, _, [inner]}), do: unwrap_block(inner)
  defp unwrap_block(other), do: other

  # Normalized n-tuples (3+ elements wrapped in :{})
  defp merge_bindings({:{}, _, args1}, {:{}, _, args2})
       when length(args1) == length(args2) do
    merged = Enum.zip(args1, args2) |> Enum.map(fn {v1, v2} -> merge_var(v1, v2) end)
    {:ok, {:{}, [], merged}}
  end

  # Literal 2-tuples (Sourceror doesn't wrap them in :{})
  defp merge_bindings({a1, b1}, {a2, b2}) do
    with {:ok, ma} <- merge_bindings(a1, a2),
         {:ok, mb} <- merge_bindings(b1, b2) do
      {:ok, {ma, mb}}
    end
  end

  defp merge_bindings(var1, var2) do
    if variable?(var1) and variable?(var2) do
      {:ok, merge_var(var1, var2)}
    else
      :error
    end
  end

  # Variables are {atom_name, metadata, context} where context is an atom (nil or Elixir).
  # Special forms like {:when, _, [x, guard]} have a list as the third element.
  defp variable?({name, _, context}) when is_atom(name) and is_atom(context),
    do: name != :{}

  defp variable?(_), do: false

  defp merge_var({name1, meta1, ctx1}, {name2, _meta2, _ctx2}) do
    s1 = Atom.to_string(name1)
    s2 = Atom.to_string(name2)

    cond do
      String.starts_with?(s1, "_") and not String.starts_with?(s2, "_") ->
        {name2, meta1, ctx1}

      String.starts_with?(s2, "_") and not String.starts_with?(s1, "_") ->
        {name1, meta1, ctx1}

      true ->
        {name1, meta1, ctx1}
    end
  end

  defp emit_patch(%Sourceror.Range{} = range, new_ast) do
    replacement = Sourceror.to_string(new_ast)
    {:ok, %{range: range, change: replacement}}
  end

  defp emit_patch(_, _), do: :skip

  # ── Check ─────────────────────────────────────────────────────────────

  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [first, second] ->
      if filter_step?(first) and map_step?(second) do
        {:ok, build_issue(first)}
      else
        nil
      end
    end)
    |> case do
      {:ok, _} = result -> result
      _ -> :error
    end
  end

  defp check_node(_), do: :error

  # ── Predicates ────────────────────────────────────────────────────────

  defp filter_step?({{:., _, [mod, :filter]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: enum_module?(mod)

  defp filter_step?(_), do: false

  defp map_step?({{:., _, [mod, :map]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: enum_module?(mod)

  defp map_step?(_), do: false

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp rebuild_pipeline([], step, []), do: step

  defp rebuild_pipeline([], step, after_) do
    Enum.reduce(after_, step, fn s, acc -> {:|>, [], [acc, s]} end)
  end

  defp rebuild_pipeline(before, step, after_) do
    pipeline =
      before
      |> Enum.reduce(fn s, acc -> {:|>, [], [acc, s]} end)
      |> then(fn head -> {:|>, [], [head, step]} end)

    Enum.reduce(after_, pipeline, fn s, acc -> {:|>, [], [acc, s]} end)
  end

  # ── Issue builders ────────────────────────────────────────────────────

  defp build_issue(filter_node) do
    {{:., meta, [_, :filter]}, _, _} = filter_node

    %Issue{
      rule: :no_filter_then_map,
      message: message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp message do
    "`Enum.filter/2` piped into `Enum.map/2` creates an unnecessary " <>
      "intermediate list. Use `for x <- enum, pred, do: transform` instead."
  end
end
