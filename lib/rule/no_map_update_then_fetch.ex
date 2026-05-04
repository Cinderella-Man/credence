defmodule Credence.Rule.NoMapUpdateThenFetch do
  @moduledoc """
  Performance rule: Detects calling `Map.update/4` (or `Map.update!/3`) on a
  map variable and then immediately reading the same key back with
  `Map.fetch!/2` or `Map.get/2`.

  `Map.update/4` traverses the map to apply the new value. Following it with
  `Map.fetch!/2` or `Map.get/2` on the same variable performs a second
  independent traversal. Calculate the new value first, then use `Map.put/3`
  so both the value and the updated map are available without a second lookup.

  ## Bad

      map = Map.update(map, key, 1, &(&1 + 1))
      val = Map.fetch!(map, key)

  ## Good

      val = case Map.fetch(map, key) do
        {:ok, v} -> (&(&1 + 1)).(v)
        :error -> 1
      end
      map = Map.put(map, key, val)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    # Pass 1: collect variables bound to Map.update/Map.update!
    {_ast, update_vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _, [{var, _, nil}, {{:., _, [{:__aliases__, _, [:Map]}, func]}, _, _}]} = node, acc
        when is_atom(var) and func in [:update, :update!] ->
          {node, MapSet.put(acc, var)}

        node, acc ->
          {node, acc}
      end)

    if MapSet.size(update_vars) == 0 do
      []
    else
      # Pass 2: find Map.fetch!/Map.get on any of those variables
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          {{:., _, [{:__aliases__, _, [:Map]}, func]}, meta, [{var, _, nil} | _]} = node, acc
          when is_atom(var) and func in [:fetch!, :get] ->
            if MapSet.member?(update_vars, var) do
              {node, [build_issue(var, func, meta) | acc]}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> transform_ast()
    |> Sourceror.to_string()
  end

  defp transform_ast({:__block__, meta, statements}) do
    {:__block__, meta, transform_block(Enum.map(statements, &transform_ast/1))}
  end

  defp transform_ast([{_, _} | _] = kw) do
    Enum.map(kw, fn {k, v} -> {k, transform_ast(v)} end)
  end

  defp transform_ast(node) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.map(&transform_ast/1)
    |> List.to_tuple()
  end

  defp transform_ast(node) when is_list(node) do
    Enum.map(node, &transform_ast/1)
  end

  defp transform_ast(node), do: node

  defp transform_block([]), do: []

  defp transform_block([stmt | rest]) do
    with {:ok, update} <- extract_map_update(stmt),
         {:ok, fetch, remaining} <- find_matching_fetch(update, rest) do
      build_replacement(update, fetch) ++ transform_block(remaining)
    else
      _err ->
        [stmt | transform_block(rest)]
    end
  end

  # ── Extract Map.update / Map.update! from assignment ─────────────────

  defp extract_map_update(
         {:=, _,
          [
            {var, _, nil},
            {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _,
             [{src, _, nil} = map_ast, key_ast, default_ast, fun_ast]}
          ]}
       )
       when is_atom(var) and is_atom(src) do
    {:ok,
     %{
       var: var,
       map: map_ast,
       key: key_ast,
       default: default_ast,
       fun: fun_ast,
       func: :update
     }}
  end

  defp extract_map_update(
         {:=, _,
          [
            {var, _, nil},
            {{:., _, [{:__aliases__, _, [:Map]}, :update!]}, _,
             [{src, _, nil} = map_ast, key_ast, fun_ast]}
          ]}
       )
       when is_atom(var) and is_atom(src) do
    {:ok,
     %{
       var: var,
       map: map_ast,
       key: key_ast,
       fun: fun_ast,
       func: :update!
     }}
  end

  defp extract_map_update(_), do: :error

  defp find_matching_fetch(%{var: var_name, key: expected_key}, rest) do
    scan_fetch(var_name, expected_key, rest, [])
  end

  defp scan_fetch(_var, _key, [], _skipped), do: :not_found

  defp scan_fetch(var, key, [stmt | rest], skipped) do
    if references_var?(stmt, var) do
      case extract_fetch_assignment(stmt, var, key) do
        {:ok, fetch_var, fetch_type} ->
          {:ok, %{assign_var: fetch_var, type: fetch_type}, Enum.reverse(skipped) ++ rest}

        :not_fetch ->
          :not_found
      end
    else
      scan_fetch(var, key, rest, [stmt | skipped])
    end
  end

  defp extract_fetch_assignment(
         {:=, _,
          [
            {fetch_var, _, nil},
            {{:., _, [{:__aliases__, _, [:Map]}, func]}, _, [{var, _, nil}, fetch_key | _]}
          ]},
         var,
         expected_key
       )
       when is_atom(fetch_var) and func in [:fetch!, :get] do
    if keys_match?(fetch_key, expected_key) do
      {:ok, fetch_var, func}
    else
      :not_fetch
    end
  end

  defp extract_fetch_assignment(_, _, _), do: :not_fetch

  defp references_var?(ast, var_name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {^var_name, _, nil} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp unwrap_block({:__block__, _, [value]}), do: value
  defp unwrap_block(other), do: other

  defp keys_match?(a, b), do: do_keys_match?(unwrap_block(a), unwrap_block(b))

  defp do_keys_match?({name, _, _}, {name, _, _}) when is_atom(name), do: true

  defp do_keys_match?(literal, literal)
       when is_atom(literal) or is_number(literal) or is_binary(literal),
       do: true

  defp do_keys_match?(_, _), do: false

  # Map.update/4 → val = case Map.fetch(map, key) do ... end; map = Map.put(...)
  defp build_replacement(
         %{
           func: :update,
           var: update_var,
           map: map_ast,
           key: key_ast,
           default: default_ast,
           fun: fun_ast
         },
         %{assign_var: fetch_var}
       ) do
    case_expr = build_case_expr(map_ast, key_ast, default_ast, fun_ast)

    val_assign = {:=, [], [{fetch_var, [], nil}, case_expr]}

    map_assign =
      {:=, [],
       [
         {update_var, [], nil},
         map_put_call(map_ast, key_ast, {fetch_var, [], nil})
       ]}

    [val_assign, map_assign]
  end

  # Map.update!/3 → val = fun.(Map.fetch!(map, key)); map = Map.put(...)
  defp build_replacement(
         %{
           func: :update!,
           var: update_var,
           map: map_ast,
           key: key_ast,
           fun: fun_ast
         },
         %{assign_var: fetch_var}
       ) do
    val_assign =
      {:=, [],
       [
         {fetch_var, [], nil},
         fun_call_ast(fun_ast, map_fetch_bang_call(map_ast, key_ast))
       ]}

    map_assign =
      {:=, [],
       [
         {update_var, [], nil},
         map_put_call(map_ast, key_ast, {fetch_var, [], nil})
       ]}

    [val_assign, map_assign]
  end

  # ── Case expression builder (string-based, Sourceror-safe) ───────────

  defp build_case_expr(map_ast, key_ast, default_ast, fun_ast) do
    map_s = Macro.to_string(map_ast)
    key_s = Macro.to_string(key_ast)
    default_s = Macro.to_string(default_ast)
    fun_s = Macro.to_string(fun_ast)

    code = """
    case Map.fetch(#{map_s}, #{key_s}) do
      {:ok, v} -> (#{fun_s}).(v)
      :error -> #{default_s}
    end
    """

    case Sourceror.parse_string!(code) do
      {:__block__, _, [node]} -> node
      node -> node
    end
  end

  defp map_fetch_bang_call(map, key) do
    {{:., [], [{:__aliases__, [], [:Map]}, :fetch!]}, [], [map, key]}
  end

  defp map_put_call(map, key, val) do
    {{:., [], [{:__aliases__, [], [:Map]}, :put]}, [], [map, key, val]}
  end

  defp fun_call_ast(fun, arg) do
    {{:., [], [fun]}, [], [arg]}
  end

  defp build_issue(var, fetch_func, meta) do
    %Issue{
      rule: :no_map_update_then_fetch,
      message:
        "`Map.#{fetch_func}/2` is called on `#{var}` right after `Map.update/4`. " <>
          "This traverses the map twice. Compute the value first with `Map.get/3`, " <>
          "then use `Map.put/3` so both the value and updated map are available.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
