defmodule Credence.Pattern.NoManualCountWithPredicate do
  @moduledoc """
  Detects hand-rolled recursive counting functions that should use `Enum.count/2`.

  ## Why this matters

  When a function counts list elements matching a predicate using manual
  tail-recursion with an accumulator, it is reimplementing `Enum.count/2`:

      # Flagged — 3-clause guard pattern
      defp do_count([], _target, acc), do: acc
      defp do_count([h | t], target, acc) when h == target,
        do: do_count(t, target, acc + 1)
      defp do_count([_h | t], target, acc),
        do: do_count(t, target, acc)

      # Flagged — 2-clause if pattern
      defp do_count([], acc), do: acc
      defp do_count([h | t], acc) do
        new_acc = if h > 0, do: acc + 1, else: acc
        do_count(t, new_acc)
      end

  ## The fix

  Each flagged group is collapsed to a single clause that delegates to
  `Enum.count/2`, threading the accumulator through unchanged:

      defp do_count(list, target, acc) when is_list(list),
        do: acc + Enum.count(list, fn h -> h == target end)

  This is a **behaviour-preserving** rewrite for every input:

  - The collapsed clause keeps the original name/arity, so callers (which
    seed the accumulator, e.g. `do_count(list, target, 0)`) are unchanged.
  - The `when is_list(list)` guard preserves the original domain: the
    multi-clause original only ever matched lists (and raised
    `FunctionClauseError` otherwise), and so does the collapsed clause.
  - `acc + Enum.count(list, pred)` reproduces `initial_acc + matches`.

  ## Detection scope (only the safely-fixable cases)

  **3-clause guard pattern** — exactly 3 clauses, all arity 3, same
  name, where:

  1. `([], _bound, acc)` returns `acc`,
  2. `([h | t], bound, acc) when <guard>` recurses `fn(t, bound, acc + 1)`,
  3. `([_h | t], bound, acc)` recurses `fn(t, bound, acc)`,

  and the `<guard>` is a **non-raising boolean** guard (comparisons,
  `and`/`or`/`not`, unary `is_*` type checks over variables/literals). A
  guard that can raise (e.g. `rem(h, 2) == 0`) is **not** flagged: a guard
  silently *skips* an element whose guard raises, but the same expression
  used as an `Enum.count/2` predicate would *raise* — a different answer.
  The bound argument must be passed through the recursion unchanged.

  **2-clause if pattern** — exactly 2 clauses, same name, where:

  1. one clause matches `[]` (in some position) and returns the trailing
     accumulator,
  2. the other matches `[h | t]` in the *same* position, binds
     `new_acc = if(<cond>, do: acc + 1, else: acc)` and recurses with the
     list tail and `new_acc`, passing every other argument through
     unchanged.

  The `<cond>` is an ordinary expression (not a guard), so it carries no
  error-swallowing semantics — moving it into `Enum.count/2` preserves its
  truthiness, side effects, and any exception it raises. No narrowing of
  `<cond>` is needed.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @comparison_ops [:==, :!=, :===, :!==, :<, :>, :<=, :>=]
  @bool_ops [:and, :or]
  @is_guards [
    :is_atom,
    :is_binary,
    :is_bitstring,
    :is_boolean,
    :is_float,
    :is_integer,
    :is_list,
    :is_map,
    :is_nil,
    :is_number,
    :is_pid,
    :is_port,
    :is_reference,
    :is_tuple
  ]

  @list_var_candidates [:list, :items, :elements, :elems, :coll, :enumerable]

  @impl true
  def check(ast, _opts) do
    ast
    |> all_blocks()
    |> Enum.flat_map(&block_issues/1)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    RuleHelpers.patches_from_ast_transform(ast, source, fn input ->
      Macro.postwalk(input, fn
        {:__block__, meta, stmts} when is_list(stmts) ->
          {:__block__, meta, collapse_stmts(stmts)}

        node ->
          node
      end)
    end)
  end

  # ── shared grouping (check and fix must agree) ─────────────────────

  defp all_blocks(ast) do
    {_ast, blocks} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, acc when is_list(stmts) -> {node, [stmts | acc]}
        node, acc -> {node, acc}
      end)

    blocks
  end

  defp block_issues(stmts) do
    stmts
    |> grouped_clauses()
    |> Enum.flat_map(fn {_key, clause_idx_list} ->
      case analyze(Enum.map(clause_idx_list, &elem(&1, 0))) do
        {:ok, info} -> [build_issue(info)]
        :error -> []
      end
    end)
  end

  defp collapse_stmts(stmts) do
    actions =
      stmts
      |> grouped_clauses()
      |> Enum.flat_map(fn {_key, clause_idx_list} ->
        case analyze(Enum.map(clause_idx_list, &elem(&1, 0))) do
          {:ok, info} ->
            idxs = clause_idx_list |> Enum.map(&elem(&1, 1)) |> Enum.sort()
            [{:replace, hd(idxs), info.clause} | Enum.map(tl(idxs), &{:remove, &1})]

          :error ->
            []
        end
      end)

    replace_map = for {:replace, i, c} <- actions, into: %{}, do: {i, c}
    remove_set = for {:remove, i} <- actions, into: MapSet.new(), do: i

    stmts
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      cond do
        Map.has_key?(replace_map, idx) -> [Map.fetch!(replace_map, idx)]
        MapSet.member?(remove_set, idx) -> []
        true -> [stmt]
      end
    end)
  end

  defp grouped_clauses(stmts) do
    stmts
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      case extract_clause(stmt) do
        {:ok, clause} -> [{clause, idx}]
        :error -> []
      end
    end)
    |> Enum.group_by(fn {clause, _idx} -> {elem(clause, 0), elem(clause, 1)} end)
  end

  # clause tuple: {name, arity, def_type, meta, patterns_tuple, body, guard_or_nil}
  defp extract_clause({def_type, meta, [{:when, _, [{fn_name, _, params}, guard]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(params) do
    {:ok, {fn_name, length(params), def_type, meta, List.to_tuple(params), body, guard}}
  end

  defp extract_clause({def_type, meta, [{fn_name, _, params}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(params) do
    {:ok, {fn_name, length(params), def_type, meta, List.to_tuple(params), body, nil}}
  end

  defp extract_clause(_), do: :error

  # ── analysis dispatch ──────────────────────────────────────────────

  defp analyze([a, _, _] = clauses) do
    if elem(a, 1) == 3, do: analyze_guard_triple(clauses), else: :error
  end

  defp analyze([a, _] = clauses) do
    if elem(a, 1) >= 2, do: analyze_if_pair(clauses), else: :error
  end

  defp analyze(_), do: :error

  # ── 3-clause guard pattern ─────────────────────────────────────────

  defp analyze_guard_triple(clauses) do
    Enum.find_value(permutations3(clauses), :error, fn {base, guarded, skip} ->
      case guard_roles(base, guarded, skip) do
        {:ok, roles} ->
          case build_guard_clause(roles) do
            {:ok, info} -> {:ok, info}
            :error -> nil
          end

        :error ->
          nil
      end
    end)
  end

  defp permutations3([a, b, c]) do
    [{a, b, c}, {a, c, b}, {b, a, c}, {b, c, a}, {c, a, b}, {c, b, a}]
  end

  defp guard_roles(base, guarded, skip) do
    fn_name = elem(base, 0)

    with true <- base_ok?(base),
         {:ok, head, bound, acc, guard} <- guarded_ok?(guarded, fn_name),
         true <- skip_ok?(skip, fn_name) do
      {:ok,
       %{
         fn_name: fn_name,
         def_type: elem(guarded, 2),
         head: head,
         bound: bound,
         acc: acc,
         guard: guard,
         line: line_of(guarded)
       }}
    else
      _ -> :error
    end
  end

  # Base: `([], _bound, acc), do: acc`
  defp base_ok?({_n, 3, _dt, _m, {p1, _p2, p3}, body, nil}) do
    empty_list_pattern?(p1) and var?(p3) and returns_var?(body, p3)
  end

  defp base_ok?(_), do: false

  # Guarded: `([h | t], bound, acc) when <safe guard>, do: fn(t, bound, acc + 1)`
  defp guarded_ok?({_n, 3, _dt, _m, {p1, p2, p3}, body, guard}, fn_name)
       when not is_nil(guard) do
    with {:ok, head, tail} <- destructure_cons(p1),
         true <- var?(head) and var?(tail) and var?(p2) and var?(p3),
         true <- safe_guard?(guard),
         true <- recurse_increment?(body, fn_name, tail, p2, p3) do
      {:ok, head, p2, p3, guard}
    else
      _ -> :error
    end
  end

  defp guarded_ok?(_, _), do: :error

  # Skip: `([_h | t], bound, acc), do: fn(t, bound, acc)` — all args passed
  # through unchanged.
  defp skip_ok?({_n, 3, _dt, _m, {p1, p2, p3}, body, nil}, fn_name) do
    with {:ok, _head, tail} <- destructure_cons(p1),
         true <- var?(p2) and var?(p3),
         {^fn_name, _, [a1, a2, a3]} <- body |> extract_do_body() |> last_expression(),
         true <- same_var?(a1, tail) and same_var?(a2, p2) and same_var?(a3, p3) do
      true
    else
      _ -> false
    end
  end

  defp skip_ok?(_, _), do: false

  defp recurse_increment?(body, fn_name, tail, bound, acc) do
    case body |> extract_do_body() |> last_expression() do
      {^fn_name, _, [a1, a2, a3]} ->
        same_var?(a1, tail) and same_var?(a2, bound) and increment_by_one?(a3, acc)

      _ ->
        false
    end
  end

  defp build_guard_clause(%{
         fn_name: fn_name,
         def_type: def_type,
         head: head,
         bound: bound,
         acc: acc,
         guard: guard,
         line: line
       }) do
    head_name = elem(head, 0)
    bound_name = elem(bound, 0)
    acc_name = elem(acc, 0)
    avoid = [head_name, bound_name, acc_name | collect_var_names(guard)]

    case fresh_list_var(avoid) do
      nil ->
        :error

      list_name ->
        params = [var(list_name), var(bound_name), var(acc_name)]
        body = count_body(acc_name, list_name, head_name, guard)

        {:ok,
         %{
           clause: make_def(def_type, fn_name, params, list_name, body),
           name: fn_name,
           arity: 3,
           def_type: def_type,
           line: line
         }}
    end
  end

  # ── 2-clause if pattern ────────────────────────────────────────────

  defp analyze_if_pair([a, b]) do
    with :error <- try_if(a, b),
         :error <- try_if(b, a) do
      :error
    end
  end

  defp try_if(base, rec) do
    with {:ok, info} <- if_recursive_ok(rec),
         true <- if_base_ok(base, info.ci, info.acc_idx),
         {:ok, built} <- build_if_clause(info) do
      {:ok, built}
    else
      _ -> :error
    end
  end

  defp if_recursive_ok({fn_name, arity, def_type, meta, pats, body, nil}) when arity >= 2 do
    acc_idx = arity - 1
    acc = elem(pats, acc_idx)

    with true <- var?(acc),
         {:ok, ci, head, tail} <- single_cons_index(pats, acc_idx),
         true <- other_params_vars?(pats, ci, acc_idx),
         {:ok, cond_ast, new_acc} <- if_block(body, acc),
         true <- recurse_if_ok?(body, fn_name, pats, ci, acc_idx, tail, new_acc) do
      {:ok,
       %{
         ci: ci,
         acc_idx: acc_idx,
         pats: pats,
         head: head,
         cond: cond_ast,
         fn_name: fn_name,
         def_type: def_type,
         acc: acc,
         line: Keyword.get(meta, :line)
       }}
    else
      _ -> :error
    end
  end

  defp if_recursive_ok(_), do: :error

  # Base: `[]` in the same position as the recursive clause's cons, trailing
  # accumulator returned unchanged.
  defp if_base_ok({_n, arity, _dt, _m, pats, body, nil}, ci, acc_idx) when arity >= 2 do
    ci < tuple_size(pats) and acc_idx < tuple_size(pats) and
      empty_list_pattern?(elem(pats, ci)) and
      var?(elem(pats, acc_idx)) and
      returns_var?(body, elem(pats, acc_idx))
  end

  defp if_base_ok(_, _, _), do: false

  defp single_cons_index(pats, acc_idx) do
    matches =
      for i <- 0..(tuple_size(pats) - 1),
          i != acc_idx,
          {:ok, head, tail} <- [destructure_cons(elem(pats, i))],
          var?(head) and var?(tail) do
        {i, head, tail}
      end

    case matches do
      [{i, head, tail}] -> {:ok, i, head, tail}
      _ -> :error
    end
  end

  defp other_params_vars?(pats, ci, acc_idx) do
    Enum.all?(0..(tuple_size(pats) - 1), fn i ->
      i == ci or i == acc_idx or var?(elem(pats, i))
    end)
  end

  # Body must be exactly `new_acc = if(cond, do: acc + 1, else: acc)` then a
  # recursive call — two expressions, no more.
  defp if_block(body, acc) do
    case extract_do_body(body) do
      {:__block__, _, [{:=, _, [nav, {:if, _, [cond_ast, clauses]}]}, _call]}
      when is_list(clauses) ->
        if var?(nav) and if_increments_acc?({:if, [], [cond_ast, clauses]}, acc) do
          {:ok, cond_ast, nav}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp recurse_if_ok?(body, fn_name, pats, ci, acc_idx, tail, new_acc) do
    case extract_do_body(body) do
      {:__block__, _, [_assign, {^fn_name, _, call_args}]}
      when is_list(call_args) and length(call_args) == tuple_size(pats) ->
        call_args
        |> Enum.with_index()
        |> Enum.all?(fn {arg, i} ->
          cond do
            i == ci -> same_var?(arg, tail)
            i == acc_idx -> same_var?(arg, new_acc)
            true -> same_var?(arg, elem(pats, i))
          end
        end)

      _ ->
        false
    end
  end

  defp build_if_clause(%{
         ci: ci,
         acc_idx: acc_idx,
         pats: pats,
         head: head,
         cond: cond_ast,
         fn_name: fn_name,
         def_type: def_type,
         line: line
       }) do
    head_name = elem(head, 0)
    acc_name = elem(elem(pats, acc_idx), 0)
    avoid = [head_name | param_var_names(pats)] ++ collect_var_names(cond_ast)

    case fresh_list_var(avoid) do
      nil ->
        :error

      list_name ->
        params =
          for i <- 0..(tuple_size(pats) - 1) do
            if i == ci, do: var(list_name), else: var(elem(elem(pats, i), 0))
          end

        body = count_body(acc_name, list_name, head_name, cond_ast)

        {:ok,
         %{
           clause: make_def(def_type, fn_name, params, list_name, body),
           name: fn_name,
           arity: tuple_size(pats),
           def_type: def_type,
           line: line
         }}
    end
  end

  # ── building the collapsed clause ──────────────────────────────────

  # `acc + Enum.count(list, fn head -> <pred> end)`
  defp count_body(acc_name, list_name, head_name, pred) do
    {:+, [],
     [
       var(acc_name),
       {{:., [], [{:__aliases__, [], [:Enum]}, :count]}, [],
        [var(list_name), {:fn, [], [{:->, [], [[var(head_name)], pred]}]}]}
     ]}
  end

  defp make_def(def_type, fn_name, params, list_name, body) do
    {def_type, [],
     [
       {:when, [], [{fn_name, [], params}, {:is_list, [], [var(list_name)]}]},
       [{{:__block__, [], [:do]}, body}]
     ]}
  end

  defp var(name), do: {name, [], nil}

  defp fresh_list_var(avoid) do
    Enum.find(@list_var_candidates, fn name -> name not in avoid end)
  end

  defp param_var_names(pats) do
    pats |> Tuple.to_list() |> Enum.flat_map(&collect_var_names/1)
  end

  defp collect_var_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {n, _, ctx} = node, acc when is_atom(n) and (is_nil(ctx) or is_atom(ctx)) ->
          {node, [n | acc]}

        node, acc ->
          {node, acc}
      end)

    names
  end

  # ── safe-guard classification ──────────────────────────────────────

  # A guard is "safe" iff it cannot raise and returns a boolean — so moving
  # it into an `Enum.count/2` predicate gives the same answer. Guards swallow
  # raised errors (skip the clause); a predicate would propagate them.
  defp safe_guard?({op, _, [l, r]}) when op in @comparison_ops do
    safe_leaf?(l) and safe_leaf?(r)
  end

  defp safe_guard?({op, _, [l, r]}) when op in @bool_ops do
    safe_guard?(l) and safe_guard?(r)
  end

  defp safe_guard?({:not, _, [x]}), do: safe_guard?(x)

  defp safe_guard?({g, _, [arg]}) when g in @is_guards, do: var?(arg)

  defp safe_guard?(_), do: false

  defp safe_leaf?(x), do: var?(x) or literal_leaf?(x)

  defp literal_leaf?(x) when is_number(x) or is_atom(x) or is_binary(x), do: true
  defp literal_leaf?({:__block__, _, [v]}), do: literal_leaf?(v)
  defp literal_leaf?(_), do: false

  # ── pattern helpers ────────────────────────────────────────────────

  defp empty_list_pattern?({:__block__, _, [[]]}), do: true
  defp empty_list_pattern?([]), do: true
  defp empty_list_pattern?(_), do: false

  defp destructure_cons({:|, _, [head, tail]}), do: {:ok, head, tail}
  defp destructure_cons({:__block__, _, [[{:|, _, [head, tail]}]]}), do: {:ok, head, tail}
  defp destructure_cons(_), do: :error

  defp var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp var?(_), do: false

  defp returns_var?(body, pattern_param) do
    last = body |> extract_do_body() |> last_expression()
    same_var?(last, pattern_param)
  end

  defp increment_by_one?({:+, _, [left, right]}, acc_param) do
    (literal_one?(left) and acc_var?(right, acc_param)) or
      (acc_var?(left, acc_param) and literal_one?(right))
  end

  defp increment_by_one?(_, _), do: false

  defp literal_one?(1), do: true
  defp literal_one?({:__block__, _, [1]}), do: true
  defp literal_one?(_), do: false

  defp acc_var?({name, _, ctx}, {name, _, _})
       when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
       do: true

  defp acc_var?(_, _), do: false

  defp if_increments_acc?({:if, _, [_cond, clauses]}, acc_param) when is_list(clauses) do
    do_body = clauses |> extract_if_clause(:do) |> unwrap_single_block()
    else_body = clauses |> extract_if_clause(:else) |> unwrap_single_block()
    increment_by_one?(do_body, acc_param) and same_var?(else_body, acc_param)
  end

  defp if_increments_acc?(_, _), do: false

  defp extract_if_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, expr} -> expr
      _ -> nil
    end)
  end

  defp unwrap_single_block({:__block__, _, [expr]}), do: expr
  defp unwrap_single_block(expr), do: expr

  defp extract_do_body(body) when is_list(body) do
    Enum.find_value(body, fn
      {{:__block__, _, [:do]}, expr} -> expr
      _ -> nil
    end)
  end

  defp extract_do_body(body), do: body

  defp last_expression({:__block__, _, exprs}) when is_list(exprs), do: List.last(exprs)
  defp last_expression(expr), do: expr

  defp same_var?({n, _, _}, {n, _, _}) when is_atom(n), do: true
  defp same_var?(_, _), do: false

  defp line_of(clause), do: clause |> elem(3) |> Keyword.get(:line)

  defp build_issue(%{def_type: def_type, name: fn_name, arity: arity} = info) do
    %Issue{
      rule: :no_manual_count_with_predicate,
      message:
        "`#{def_type} #{fn_name}/#{arity}` is a manual recursive counting function " <>
          "that reimplements `Enum.count/2`.\n\n" <>
          "Use `Enum.count(list, predicate)` instead — it is clearer " <>
          "and avoids unnecessary code.",
      meta: %{line: Map.get(info, :line)}
    }
  end
end
