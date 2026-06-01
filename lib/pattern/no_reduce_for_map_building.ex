defmodule Credence.Pattern.NoReduceForMapBuilding do
  @moduledoc """
  Detects `Enum.reduce/3` with an empty-map accumulator `%{}` and a body
  consisting solely of `Map.put(acc, key, value)`, and suggests `Map.new/2`
  instead. Also detects `Enum.reduce/3` building a `MapSet` via
  `MapSet.put/2` and suggests `MapSet.new/1`.

  ## Why this matters

  LLMs frequently produce:

      Enum.reduce(list, %{}, fn x, acc ->
        Map.put(acc, x, String.length(x))
      end)

  when the idiomatic Elixir equivalent is:

      Map.new(list, fn x -> {x, String.length(x)} end)

  Similarly, LLMs may build a MapSet via reduce:

      Enum.reduce(list, MapSet.new(), fn x, acc -> MapSet.put(acc, x) end)

  when the idiomatic equivalent is:

      MapSet.new(list)

  `Map.new/2` and `MapSet.new/1` communicate intent directly and avoid
  manual accumulator threading.

  ## Flagged patterns

  | Pattern | Suggested replacement |
  | ------- | --------------------- |
  | `Enum.reduce(enum, %{}, fn x, acc -> Map.put(acc, k, v) end)` | `Map.new(enum, fn x -> {k, v} end)` |
  | `enum \|> Enum.reduce(%{}, fn x, acc -> Map.put(acc, k, v) end)` | `enum \|> Map.new(fn x -> {k, v} end)` |
  | `Enum.reduce(enum, MapSet.new(), fn x, acc -> MapSet.put(acc, x) end)` | `MapSet.new(enum)` |
  | `enum \|> Enum.reduce(MapSet.new(), fn x, acc -> MapSet.put(acc, x) end)` | `enum \|> MapSet.new()` |

  Only the simplest case is matched: the anonymous function body must be
  a single `Map.put(acc, key, value)` or `MapSet.put(acc, value)` call
  (or a single-expression block), and neither `key`/`value` nor the
  MapSet value may reference `acc`.
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Direct form: Enum.reduce(enum, %{}, fn elem, acc -> Map.put(acc, ...) end)
      # Direct form: Enum.reduce(enum, MapSet.new(), fn elem, acc -> MapSet.put(acc, ...) end)
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, args} = node
      when is_list(args) ->
        with :error <- fix_map_direct(args),
             :error <- fix_mapset_direct(args) do
          node
        end

      # Piped form: enum |> Enum.reduce(%{}, fn elem, acc -> Map.put(acc, ...) end)
      # Piped form: enum |> Enum.reduce(MapSet.new(), fn elem, acc -> MapSet.put(acc, ...) end)
      {:|>, pipe_meta, [enum, {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, args}]} =
          node
      when is_list(args) ->
        with :error <- fix_map_piped(args, pipe_meta, enum),
             :error <- fix_mapset_piped(args, pipe_meta, enum) do
          node
        end

      node ->
        node
    end)
  end

  defp fix_map_direct(args) do
    case extract_parts(args) do
      {:ok, enum, elem_var, key_expr, value_expr} ->
        build_map_new(enum, elem_var, key_expr, value_expr)

      :error ->
        :error
    end
  end

  defp fix_mapset_direct(args) do
    case extract_mapset_parts(args) do
      {:ok, enum} when not is_nil(enum) ->
        build_mapset_new(enum)

      _ ->
        :error
    end
  end

  defp fix_map_piped(args, pipe_meta, enum) do
    case extract_parts(args) do
      {:ok, _, elem_var, key_expr, value_expr} ->
        map_new_fn = build_map_new_fn(elem_var, key_expr, value_expr)
        {:|>, pipe_meta, [enum, map_new_call(map_new_fn)]}

      :error ->
        :error
    end
  end

  defp fix_mapset_piped(args, pipe_meta, enum) do
    case extract_mapset_parts(args) do
      {:ok, _} ->
        mapset_new = {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], []}
        {:|>, pipe_meta, [enum, mapset_new]}

      _ ->
        :error
    end
  end

  # ── check ───────────────────────────────────────────────────────────

  defp check_node({{:., meta, [{:__aliases__, _, [:Enum]}, :reduce]}, _, args})
       when is_list(args) do
    with :error <- check_map_reduce(args, meta),
         :error <- check_mapset_reduce(args, meta) do
      :error
    end
  end

  defp check_node(_), do: :error

  defp check_map_reduce(args, meta) do
    case extract_parts(args) do
      {:ok, _, _, _, _} ->
        {:ok,
         %Issue{
           rule: :no_reduce_for_map_building,
           message:
             "`Enum.reduce/3` building a map via `Map.put/3` can be replaced with " <>
               "`Map.new/2`. `Map.new(enum, fn elem -> {key, value} end)` is clearer " <>
               "and more idiomatic.",
           meta: %{line: Keyword.get(meta, :line)}
         }}

      :error ->
        :error
    end
  end

  defp check_mapset_reduce(args, meta) do
    case extract_mapset_parts(args) do
      {:ok, _} ->
        {:ok,
         %Issue{
           rule: :no_reduce_for_map_building,
           message:
             "`Enum.reduce/3` building a MapSet via `MapSet.put/2` can be replaced with " <>
               "`MapSet.new/1`. `MapSet.new(enum)` is clearer and more idiomatic.",
           meta: %{line: Keyword.get(meta, :line)}
         }}

      :error ->
        :error
    end
  end

  # ── extraction ──────────────────────────────────────────────────────

  # 3-arg form (direct call): [enum, %{}, fn ...]
  defp extract_parts([enum, {:%{}, _, []}, fn_ast]) do
    with {:ok, elem_var, key_expr, value_expr} <- extract_fn_parts(fn_ast) do
      {:ok, enum, elem_var, key_expr, value_expr}
    end
  end

  # 2-arg form (piped — first arg comes from the pipe): [%{}, fn ...]
  defp extract_parts([{:%{}, _, []}, fn_ast]) do
    with {:ok, elem_var, key_expr, value_expr} <- extract_fn_parts(fn_ast) do
      {:ok, nil, elem_var, key_expr, value_expr}
    end
  end

  defp extract_parts(_), do: :error

  # 3-arg form: [enum, MapSet.new(), fn ...]
  defp extract_mapset_parts([enum, {{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []}, fn_ast]) do
    case extract_mapset_fn_parts(fn_ast) do
      {:ok, _} -> {:ok, enum}
      :error -> :error
    end
  end

  # 2-arg form (piped): [MapSet.new(), fn ...]
  defp extract_mapset_parts([{{:., _, [{:__aliases__, _, [:MapSet]}, :new]}, _, []}, fn_ast]) do
    case extract_mapset_fn_parts(fn_ast) do
      {:ok, _} -> {:ok, nil}
      :error -> :error
    end
  end

  defp extract_mapset_parts(_), do: :error

  defp extract_fn_parts({:fn, _, [{:->, _, [[{elem, _, ectx}, {acc, _, actx}], body]}]})
       when is_atom(elem) and is_atom(ectx) and is_atom(acc) and is_atom(actx) do
    with {:ok, key_expr, value_expr} <- extract_map_put(body, acc) do
      # Reject if key or value references the accumulator — the rewrite
      # removes `acc`, so such references would be invalid.
      if var_in_ast?(key_expr, acc) or var_in_ast?(value_expr, acc) do
        :error
      else
        {:ok, {elem, ectx}, key_expr, value_expr}
      end
    end
  end

  defp extract_fn_parts(_), do: :error

  # Matches fn elem, acc -> MapSet.put(acc, elem) end (identity case only).
  defp extract_mapset_fn_parts({:fn, _, [{:->, _, [[{elem, _, ectx}, {acc, _, actx}], body]}]})
       when is_atom(elem) and is_atom(ectx) and is_atom(acc) and is_atom(actx) do
    case extract_mapset_put(body, acc) do
      {:ok, {^elem, _, value_ctx}} when is_atom(value_ctx) ->
        {:ok, {elem, ectx}}

      _ ->
        :error
    end
  end

  # Matches &MapSet.put(&2, &1) capture form.
  defp extract_mapset_fn_parts(
         {:&, _,
          [
            {{:., _, [{:__aliases__, _, [:MapSet]}, :put]}, _,
             [{:&, _, [2]}, {:&, _, [1]}]}
          ]}
       ) do
    {:ok, :capture}
  end

  defp extract_mapset_fn_parts(_), do: :error

  # Matches Map.put(acc, key, value) where acc matches the reduce accumulator.
  defp extract_map_put(
         {{:., _, [{:__aliases__, _, [:Map]}, :put]}, _,
          [{acc_name, _, acc_ctx}, key_expr, value_expr]},
         acc_name
       )
       when is_atom(acc_ctx),
       do: {:ok, key_expr, value_expr}

  defp extract_map_put({:__block__, _, [single]}, acc_name),
    do: extract_map_put(single, acc_name)

  defp extract_map_put(_, _), do: :error

  # Matches MapSet.put(acc, value) where acc matches the reduce accumulator.
  defp extract_mapset_put(
         {{:., _, [{:__aliases__, _, [:MapSet]}, :put]}, _,
          [{acc_name, _, acc_ctx}, value_expr]},
         acc_name
       )
       when is_atom(acc_ctx),
       do: {:ok, value_expr}

  defp extract_mapset_put({:__block__, _, [single]}, acc_name),
    do: extract_mapset_put(single, acc_name)

  defp extract_mapset_put(_, _), do: :error

  # ── fix builders ────────────────────────────────────────────────────

  defp build_map_new(enum, elem_var, key_expr, value_expr) do
    map_new_fn = build_map_new_fn(elem_var, key_expr, value_expr)
    {{:., [], [{:__aliases__, [], [:Map]}, :new]}, [], [enum, map_new_fn]}
  end

  defp build_map_new_fn({elem, ectx}, key_expr, value_expr) do
    tuple = {:{}, [], [key_expr, value_expr]}
    {:fn, [], [{:->, [], [[{elem, [], ectx}], tuple]}]}
  end

  defp map_new_call(map_new_fn) do
    {{:., [], [{:__aliases__, [], [:Map]}, :new]}, [], [map_new_fn]}
  end

  defp build_mapset_new(enum) do
    {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], [enum]}
  end

  # ── helpers ─────────────────────────────────────────────────────────

  defp var_in_ast?(ast, var_name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {^var_name, _, ctx} = node, _acc when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end
end
