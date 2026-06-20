defmodule Credence.Pattern.NoMapUpdateThenFetch do
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
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    # Mirror the fix exactly: a `var = Map.update(map, key, …)` whose updated
    # variable is next *referenced* (in the same block) by a `Map.fetch!/get(var,
    # key)` with a MATCHING key. The earlier two-pass version flagged any
    # `Map.fetch!/get` on a name bound by `Map.update` anywhere in the file —
    # across functions, non-adjacent, ignoring the key — none of which the fix
    # can act on. Walking blocks with the fix's own pairing keeps check and fix
    # in lock-step.
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) ->
          {node, acc ++ detect_in_block(stmts)}

        node, acc ->
          {node, acc}
      end)

    issues
  end

  defp detect_in_block([]), do: []

  defp detect_in_block([stmt | rest]) do
    with {:ok, update} <- extract_map_update(stmt),
         {:ok, fetch, remaining} <- find_matching_fetch(update, rest) do
      [build_issue(update.var, fetch.type, fetch.meta) | detect_in_block(remaining)]
    else
      _ -> detect_in_block(rest)
    end
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)
    RuleHelpers.patches_from_ast_transform(ast, source, &transform_ast/1)
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
        {:ok, fetch_var, fetch_type, meta} ->
          {:ok, %{assign_var: fetch_var, type: fetch_type, meta: meta},
           Enum.reverse(skipped) ++ rest}

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
            {{:., _, [{:__aliases__, _, [:Map]}, func]}, meta, [{var, _, nil}, fetch_key | _]}
          ]},
         var,
         expected_key
       )
       when is_atom(fetch_var) and func in [:fetch!, :get] do
    if keys_match?(fetch_key, expected_key) do
      {:ok, fetch_var, func, meta}
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
