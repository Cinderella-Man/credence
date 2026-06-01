defmodule Credence.Pattern.NoReduceForMapBuilding do
  @moduledoc """
  Detects `Enum.reduce/3` with an empty-map accumulator `%{}` and a body
  consisting solely of `Map.put(acc, key, value)`, and suggests `Map.new/2`
  instead.

  ## Why this matters

  LLMs frequently produce:

      Enum.reduce(list, %{}, fn x, acc ->
        Map.put(acc, x, String.length(x))
      end)

  when the idiomatic Elixir equivalent is:

      Map.new(list, fn x -> {x, String.length(x)} end)

  `Map.new/2` communicates "build a new map" directly and avoids manual
  accumulator threading.

  ## Flagged patterns

  | Pattern | Suggested replacement |
  | ------- | --------------------- |
  | `Enum.reduce(enum, %{}, fn x, acc -> Map.put(acc, k, v) end)` | `Map.new(enum, fn x -> {k, v} end)` |
  | `enum \|> Enum.reduce(%{}, fn x, acc -> Map.put(acc, k, v) end)` | `enum \|> Map.new(fn x -> {k, v} end)` |

  Only the simplest case is matched: the anonymous function body must be
  a single `Map.put(acc, key, value)` call (or a single-expression block),
  and neither `key` nor `value` may reference `acc`.
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
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, args} = node
      when is_list(args) ->
        case extract_parts(args) do
          {:ok, enum, elem_var, key_expr, value_expr} ->
            build_map_new(enum, elem_var, key_expr, value_expr)

          :error ->
            node
        end

      # Piped form: enum |> Enum.reduce(%{}, fn elem, acc -> Map.put(acc, ...) end)
      {:|>, pipe_meta, [enum, {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, args}]} =
          node
      when is_list(args) ->
        case extract_parts(args) do
          {:ok, _, elem_var, key_expr, value_expr} ->
            map_new_fn = build_map_new_fn(elem_var, key_expr, value_expr)
            {:|>, pipe_meta, [enum, map_new_call(map_new_fn)]}

          :error ->
            node
        end

      node ->
        node
    end)
  end

  # ── check ───────────────────────────────────────────────────────────

  defp check_node({{:., meta, [{:__aliases__, _, [:Enum]}, :reduce]}, _, args})
       when is_list(args) do
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

  defp check_node(_), do: :error

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
