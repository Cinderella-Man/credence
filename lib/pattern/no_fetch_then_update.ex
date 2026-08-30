defmodule Credence.Pattern.NoFetchThenUpdate do
  @moduledoc """
  Detects `Map.update!/3` or `Map.update/4` called inside a
  `case Map.fetch/2` `{:ok, val}` branch on the same map and key, and
  rewrites the redundant update into a `Map.put/3`.

  Inside the `{:ok, val}` branch the key is known to be present and its
  current value is bound to `val`. `Map.update!`/`Map.update` then look the
  key up a *second* time only to apply a function to that same value. Since
  the value is already in hand as `val`, the same result is produced by
  `Map.put(map, key, fun.(val))` — one map lookup is saved.

  ## Bad

      case Map.fetch(counts, key) do
        {:ok, n} ->
          {n, Map.update!(counts, key, &(&1 + 1))}

        :error ->
          {0, Map.put(counts, key, 1)}
      end

  ## Good

      case Map.fetch(counts, key) do
        {:ok, n} ->
          {n, Map.put(counts, key, (&(&1 + 1)).(n))}

        :error ->
          {0, Map.put(counts, key, 1)}
      end

  ## Why the fix applies the captured function instead of inlining it

  `Map.update!(map, key, fun)` with the key present is exactly
  `Map.put(map, key, fun.(val))`: `fun` is evaluated once and applied once
  to the current value, which is `val`. Rather than inlining the body of an
  arbitrary `fun` (hard and error-prone for captures), the fix simply
  applies it — `fun.(val)` — which is behaviour-identical for every input.
  `mix format` tidies the rendered call afterwards.

  ## Safety narrowing

  The rewrite is only behaviour-preserving when:

  - the fetched map and key are **simple** (a bare variable or a literal),
    so re-mentioning them in `Map.put` cannot evaluate a side effect twice
    or read a different value, and
  - the `{:ok, val}` branch body contains **no binding constructs**
    (`=`, `fn`, `for`, `with`, `case`, `cond`, `receive`, `try`), so the
    map, key and `val` bindings observed at the `Map.update` call are the
    same ones the `Map.fetch` produced (no rebinding or shadowing).

  Calls that fall outside this core are deliberately left untouched.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @binding_construct_forms [:=, :fn, :for, :with, :case, :cond, :receive, :try]

  @impl true
  def check(ast, _opts) do
    if has_map_alias?(ast), do: [], else: collect_issues(ast)
  end

  @impl true
  def fix_patches(ast, _opts) do
    if has_map_alias?(ast) do
      []
    else
      transformed = transform_code(ast, &rewrite_fetch_case/1)
      Credence.RuleHelpers.patches_from_diff(ast, transformed)
    end
  end

  defp collect_issues({:quote, _, _}), do: []

  defp collect_issues(node) do
    own =
      case fetch_case_info(node) do
        {:ok, bound_val, body, fetch_map, fetch_key} ->
          body
          |> fixable_updates(fetch_map, fetch_key)
          |> Enum.map(&build_issue(&1, bound_val))

        :none ->
          []
      end

    own ++ Enum.flat_map(code_child_nodes(node), &collect_issues/1)
  end

  # A textual `Map` is not Elixir.Map when a source aliases another module to
  # that name. Conservatively leave such a source alone; without expansion in
  # a compiler environment the two meanings cannot be distinguished reliably.
  defp has_map_alias?(ast) do
    any_code?(ast, fn
      {:alias, _, [_, opts]} when is_list(opts) -> alias_as_map?(opts)
      _ -> false
    end)
  end

  defp alias_as_map?(opts) do
    Enum.any?(opts, fn
      {{:__block__, _, [:as]}, {:__aliases__, _, [:Map]}} -> true
      {:as, {:__aliases__, _, [:Map]}} -> true
      _ -> false
    end)
  end

  defp any_code?({:quote, _, _}, _predicate), do: false

  defp any_code?(node, predicate) do
    predicate.(node) or Enum.any?(code_child_nodes(node), &any_code?(&1, predicate))
  end

  defp transform_code({:quote, _, _} = node, _fun), do: node

  defp transform_code(node, fun) do
    node
    |> map_code_child_nodes(&transform_code(&1, fun))
    |> fun.()
  end

  # --- Detection of the `case Map.fetch(map, key) do {:ok, val} -> ... end` shape

  # Returns {:ok, bound_val, ok_branch_body, fetch_map, fetch_key} | :none.
  # Only fires when map and key are simple (variable or literal).
  defp fetch_case_info(
         {:case, _case_meta,
          [
            {{:., _, [{:__aliases__, _, [:Map]}, :fetch]}, _, [fetch_map, fetch_key]},
            [{{:__block__, _, [:do]}, clauses}]
          ]}
       )
       when is_list(clauses) do
    if simple?(fetch_map) and simple?(fetch_key) do
      Enum.find_value(clauses, :none, fn
        # Sourceror renders `{:ok, val} -> body` as:
        # {:->, _, [[{:__block__, _, [{{:__block__, _, [:ok]}, {val, _, nil}}]}], body]}
        {:->, _line_meta,
         [
           [{:__block__, _, [{{:__block__, _, [:ok]}, {bound_val, _, nil}}]}],
           body
         ]}
        when is_atom(bound_val) and bound_val != :_ ->
          {:ok, bound_val, body, fetch_map, fetch_key}

        _ ->
          nil
      end)
    else
      :none
    end
  end

  defp fetch_case_info(_), do: :none

  # A bare variable or a plain literal — pure to re-mention, evaluates to the
  # same value every time. Anything else (calls, operators, data structures)
  # could carry a side effect or read differently, so it is rejected.
  defp simple?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true

  defp simple?({:__block__, _, [lit]})
       when is_atom(lit) or is_number(lit) or is_binary(lit),
       do: true

  defp simple?(_), do: false

  # --- The safe core: matching update calls in the branch body

  # Lists the `Map.update`/`Map.update!` nodes in `body` that are safe to
  # rewrite. Empty when the body has any binding construct (which could
  # rebind/shadow map, key or val between the fetch and the update).
  defp fixable_updates(body, fetch_map, fetch_key) do
    if has_binding_construct?(body) do
      []
    else
      collect_updates(body, fetch_map, fetch_key)
    end
  end

  defp has_binding_construct?(ast) do
    any_code?(ast, fn
      {form, _, _} when form in @binding_construct_forms -> true
      _ -> false
    end)
  end

  # Custom walk that gathers matching update calls WITHOUT descending into a
  # matched call's own subtree, nor into captures (`&`) / anonymous functions
  # (`fn`). This keeps gathered nodes non-overlapping and never inside a
  # capture (where a bare `&1` would be left dangling by a rewrite).
  defp collect_updates(ast, fetch_map, fetch_key) do
    case match_update(ast, fetch_map, fetch_key) do
      {:ok, node} ->
        [node]

      :no ->
        ast
        |> child_nodes()
        |> Enum.flat_map(&collect_updates(&1, fetch_map, fetch_key))
    end
  end

  # Mirror of collect_updates that rebuilds the tree with each matched update
  # rewritten to a Map.put call.
  defp rewrite_updates(ast, fetch_map, fetch_key, bound_val) do
    case match_update(ast, fetch_map, fetch_key) do
      {:ok, node} ->
        build_put(node, bound_val)

      :no ->
        map_child_nodes(ast, &rewrite_updates(&1, fetch_map, fetch_key, bound_val))
    end
  end

  # Recognises `Map.update!(map, key, fun)` and `Map.update(map, key, default,
  # fun)` whose map and key match the fetch's (both already simple).
  defp match_update(
         {{:., _, [{:__aliases__, _, [:Map]}, :update!]}, _meta, [m, k, _fun]} = node,
         fetch_map,
         fetch_key
       ) do
    if same?(m, fetch_map) and same?(k, fetch_key), do: {:ok, node}, else: :no
  end

  defp match_update(
         {{:., _, [{:__aliases__, _, [:Map]}, :update]}, _meta, [m, k, _default, _fun]} = node,
         fetch_map,
         fetch_key
       ) do
    if same?(m, fetch_map) and same?(k, fetch_key), do: {:ok, node}, else: :no
  end

  defp match_update(_, _, _), do: :no

  defp same?(a, b), do: Macro.to_string(a) == Macro.to_string(b)

  # Children for the pruning walk: never descend into captures or fns.
  defp child_nodes({:&, _, _}), do: []
  defp child_nodes({:fn, _, _}), do: []
  defp child_nodes({:quote, _, _}), do: []

  defp child_nodes({form, _meta, args}) when is_list(args) do
    if is_tuple(form), do: [form | args], else: args
  end

  defp child_nodes({a, b}), do: [a, b]
  defp child_nodes(list) when is_list(list), do: list
  defp child_nodes(_), do: []

  defp map_child_nodes({:&, _, _} = node, _fun), do: node
  defp map_child_nodes({:fn, _, _} = node, _fun), do: node
  defp map_child_nodes({:quote, _, _} = node, _fun), do: node

  defp map_child_nodes({form, meta, args}, fun) when is_list(args) do
    {if(is_tuple(form), do: fun.(form), else: form), meta, Enum.map(args, fun)}
  end

  defp map_child_nodes({a, b}, fun), do: {fun.(a), fun.(b)}
  defp map_child_nodes(list, fun) when is_list(list), do: Enum.map(list, fun)
  defp map_child_nodes(other, _fun), do: other

  # General code traversal used to find fetch cases. Unlike the update walker,
  # it enters function bodies, but quoted AST is data and is always opaque.
  defp code_child_nodes({form, _meta, args}) when is_list(args) do
    if is_tuple(form), do: [form | args], else: args
  end

  defp code_child_nodes({a, b}), do: [a, b]
  defp code_child_nodes(list) when is_list(list), do: list
  defp code_child_nodes(_), do: []

  defp map_code_child_nodes({form, meta, args}, fun) when is_list(args) do
    {if(is_tuple(form), do: fun.(form), else: form), meta, Enum.map(args, fun)}
  end

  defp map_code_child_nodes({a, b}, fun), do: {fun.(a), fun.(b)}
  defp map_code_child_nodes(list, fun) when is_list(list), do: Enum.map(list, fun)
  defp map_code_child_nodes(other, _fun), do: other

  # --- Building output

  # `Map.update*(map, key, ..., fun)` -> `Map.put(map, key, fun.(val))`.
  # Reuses the original map, key and fun subtrees verbatim.
  defp build_put({_callee, _meta, args}, bound_val) do
    {map, key, default, fun} =
      case args do
        [m, k, fun] -> {m, k, nil, fun}
        [m, k, default, fun] -> {m, k, default, fun}
      end

    applied = {{:., [], [fun]}, [], [{bound_val, [], nil}]}

    put = {{:., [], [{:__aliases__, [], [:Map]}, :put]}, [], [map, key, applied]}

    if default && !simple?(default) do
      {:case, [], [default, [do: [{:->, [], [[{:_, [], nil}], put]}]]]}
    else
      put
    end
  end

  defp rewrite_fetch_case(node) do
    case fetch_case_info(node) do
      {:ok, bound_val, body, fetch_map, fetch_key} ->
        if has_binding_construct?(body) do
          node
        else
          replace_ok_branch_body(node, bound_val, fetch_map, fetch_key)
        end

      :none ->
        node
    end
  end

  defp replace_ok_branch_body(
         {:case, case_meta, [fetch, [{do_kw, clauses}]]},
         bound_val,
         fetch_map,
         fetch_key
       ) do
    new_clauses =
      Enum.map(clauses, fn
        {:->, line_meta,
         [
           [{:__block__, _, [{{:__block__, _, [:ok]}, {^bound_val, _, nil}}]}] = pattern,
           body
         ]} ->
          {:->, line_meta, [pattern, rewrite_updates(body, fetch_map, fetch_key, bound_val)]}

        other ->
          other
      end)

    {:case, case_meta, [fetch, [{do_kw, new_clauses}]]}
  end

  defp build_issue({_callee, call_meta, _args} = node, bound_val) do
    {map, key, _fun} =
      case node do
        {_, _, [m, k, _fun]} -> {m, k, nil}
        {_, _, [m, k, _default, _fun]} -> {m, k, nil}
      end

    map_s = Macro.to_string(map)
    key_s = Macro.to_string(key)
    line = Keyword.get(call_meta, :line)

    %Issue{
      rule: :no_fetch_then_update,
      message:
        "`Map.update` on `#{map_s}` key `#{key_s}` inside a `case Map.fetch` " <>
          "`{:ok, #{bound_val}}` branch re-reads the value already bound as " <>
          "`#{bound_val}`. Use `Map.put(#{map_s}, #{key_s}, ...)` instead.",
      meta: %{line: line}
    }
  end
end
