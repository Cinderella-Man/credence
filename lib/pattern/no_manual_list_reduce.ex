defmodule Credence.Pattern.NoManualListReduce do
  @moduledoc """
  Detects hand-rolled recursive list-folding functions that should use
  `Enum.reduce/3`.

  ## Why this matters

  The classic two-clause recursive fold — an empty-list base returning the
  accumulator, and a `[h | t]` clause that recurses on the tail with an updated
  accumulator — reimplements `Enum.reduce/3` with no benefit:

      # Flagged (arity 2)
      defp sum([], acc), do: acc
      defp sum([h | t], acc), do: sum(t, acc + h)

      # Flagged (arity 3, extra argument threaded through unchanged)
      defp scale([], _factor, acc), do: acc
      defp scale([h | t], factor, acc), do: scale(t, factor, acc + h * factor)

  ## The fix

  Each flagged group collapses to a single clause delegating to `Enum.reduce/3`,
  moving the accumulator-update expression into the reducer function:

      defp sum(list, acc) when is_list(list),
        do: Enum.reduce(list, acc, fn h, acc -> acc + h end)

  This is **behaviour-preserving for every input**:

  - **Domain.** The collapsed clause keeps the original name/arity and guards
    `when is_list(list)`. The two-clause original only ever matched `[]` or
    `[_ | _]` (and raised `FunctionClauseError` otherwise). `is_list/1` is true
    for *both* proper and improper lists and false for everything else — exactly
    the original domain. Maps/ranges/scalars raise `FunctionClauseError` on both
    sides; an improper list raises `FunctionClauseError` on both sides
    (`Enum.reduce` and the manual recursion both fail the same way on the
    improper tail — verified).
  - **Same walk, same accumulator.** `Enum.reduce/3` folds the list head-to-tail,
    calling `fun.(element, accumulator)`. The manual recursion walks the same
    order, computing the same updated accumulator at each step from the same
    `h`/`acc`. For `[]` both return the seed accumulator untouched (the reducer
    runs zero times). The accumulator-update expression is moved *verbatim* into
    the reducer body, so its value, side effects, evaluation count (once per
    element), and any exception it raises are identical.

  ## Detection scope (only the safely-fixable cases)

  Exactly **2 clauses**, same name, arity **≥ 2**, no guards, where some
  assignment of the clauses fills these two roles. The accumulator is the
  **last** parameter; exactly one other parameter is the list (cons) position;
  every remaining parameter is a plain variable threaded through unchanged.

  1. **Base** — `([], …, acc)`: `[]` at the cons position, the last parameter a
     variable, whose body is a *single expression* returning exactly that
     variable.
  2. **Recurse** — `([h | t], …, acc)`: `[h | t]` (both variables) at the cons
     position, whose body is *exactly* the self-call `fn(…, t, …, <expr>)` — the
     tail `t` at the cons position, an accumulator-update `<expr>` at the last
     position, and every other argument the matching parameter unchanged.

  ### Why these narrowings (each drops a different-answer case)

  - **Single-expression bodies only.** Each role's body must be its one
    expression (the accumulator variable / the self-call), never a
    multi-statement block. A block could carry a side effect that the
    reducer-based rewrite would drop or move — a different answer.
  - **No tail reference in the update.** The accumulator-update expression must
    not mention the tail variable `t`. Inside `Enum.reduce/3` the reducer sees
    only the element and the accumulator — `t` is not in scope — so any update
    that read the remaining tail could not be reproduced. (Every other variable
    the update can mention — the head, the accumulator, and the threaded
    parameters — *is* in scope in the collapsed clause / reducer.) Such groups
    are left untouched.
  - **Accumulator last, single cons position.** Only the shape with the
    accumulator as the final parameter and exactly one cons (list) parameter is
    flagged; other layouts are dropped rather than risk a mis-collapse.

  ## Bad

      defmodule BadNMLR do
        def sum([], acc), do: acc
        def sum([h | t], acc), do: sum(t, acc + h)
      end

  ## Good

      defmodule BadNMLR do
        def sum(list, acc) when is_list(list), do: Enum.reduce(list, acc, fn h, acc -> acc + h end)
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

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

  # ── analysis ───────────────────────────────────────────────────────

  defp analyze([a, _] = clauses) do
    if elem(a, 1) >= 2, do: analyze_pair(clauses), else: :error
  end

  defp analyze(_), do: :error

  defp analyze_pair([a, b]) do
    with :error <- try_reduce(a, b) do
      try_reduce(b, a)
    end
  end

  defp try_reduce(base, rec) do
    with {:ok, info} <- recursive_ok(rec),
         true <- base_ok(base, info.ci, info.acc_idx),
         {:ok, built} <- build_clause(info) do
      {:ok, built}
    else
      _ -> :error
    end
  end

  # Recurse: `([h | t], …, acc), do: fn(…, t, …, <update>)` — single self-call,
  # tail at the cons position, `<update>` at the accumulator position, every
  # other argument the matching parameter unchanged, and `<update>` free of `t`.
  defp recursive_ok({fn_name, arity, def_type, meta, pats, body, nil}) when arity >= 2 do
    acc_idx = arity - 1
    acc = elem(pats, acc_idx)

    with true <- var?(acc),
         {:ok, ci, head, tail} <- single_cons_index(pats, acc_idx),
         true <- other_params_vars?(pats, ci, acc_idx),
         true <- distinct_bindings?(pats, ci, acc_idx, head, tail),
         {:ok, update} <- recursive_call_ok(body, fn_name, pats, ci, acc_idx, tail),
         true <- tail_not_referenced?(update, tail) do
      {:ok,
       %{
         ci: ci,
         acc_idx: acc_idx,
         pats: pats,
         head: head,
         acc: acc,
         update: update,
         fn_name: fn_name,
         def_type: def_type,
         line: Keyword.get(meta, :line)
       }}
    else
      _ -> :error
    end
  end

  defp recursive_ok(_), do: :error

  # Base: `[]` at the cons position, trailing accumulator returned unchanged as
  # a single expression.
  defp base_ok({_n, arity, _dt, _m, pats, body, nil}, ci, acc_idx) when arity >= 2 do
    ci < tuple_size(pats) and acc_idx < tuple_size(pats) and
      empty_list_pattern?(elem(pats, ci)) and
      var?(elem(pats, acc_idx)) and
      returns_var?(body, elem(pats, acc_idx))
  end

  defp base_ok(_, _, _), do: false

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

  # All variables the recursive clause binds directly (head, tail, accumulator,
  # and each threaded parameter) must have distinct names. A repeated name is an
  # equality-constraint match (`f([acc | t], acc)`) the collapse can't reproduce
  # and would emit invalid reducer params like `fn acc, acc -> ... end`.
  defp distinct_bindings?(pats, ci, acc_idx, head, tail) do
    threaded =
      for i <- 0..(tuple_size(pats) - 1), i != ci and i != acc_idx, do: elem(elem(pats, i), 0)

    names = [elem(head, 0), elem(tail, 0), elem(elem(pats, acc_idx), 0) | threaded]
    length(Enum.uniq(names)) == length(names)
  end

  # Body must be exactly the self-call, threading the tail at `ci`, an arbitrary
  # update expression at `acc_idx`, and every other parameter through unchanged.
  defp recursive_call_ok(body, fn_name, pats, ci, acc_idx, tail) do
    case body |> extract_do_body() |> unwrap_single() do
      {^fn_name, _, call_args}
      when is_list(call_args) and length(call_args) == tuple_size(pats) ->
        threaded? =
          call_args
          |> Enum.with_index()
          |> Enum.all?(fn {arg, i} ->
            cond do
              i == ci -> same_var?(arg, tail)
              i == acc_idx -> true
              true -> same_var?(arg, elem(pats, i))
            end
          end)

        if threaded?, do: {:ok, Enum.at(call_args, acc_idx)}, else: :error

      _ ->
        :error
    end
  end

  defp tail_not_referenced?(update, tail) do
    elem(tail, 0) not in collect_var_names(update)
  end

  # ── building the collapsed clause ──────────────────────────────────

  defp build_clause(%{
         ci: ci,
         acc_idx: acc_idx,
         pats: pats,
         head: head,
         acc: acc,
         update: update,
         fn_name: fn_name,
         def_type: def_type,
         line: line
       }) do
    head_name = elem(head, 0)
    acc_name = elem(acc, 0)
    avoid = [head_name, acc_name | param_var_names(pats)] ++ collect_var_names(update)

    case fresh_list_var(avoid) do
      nil ->
        :error

      list_name ->
        params =
          for i <- 0..(tuple_size(pats) - 1) do
            cond do
              i == ci -> var(list_name)
              i == acc_idx -> var(acc_name)
              true -> var(elem(elem(pats, i), 0))
            end
          end

        body = reduce_body(list_name, acc_name, head_name, update)

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

  # `Enum.reduce(list, acc, fn head, acc -> <update> end)`
  defp reduce_body(list_name, acc_name, head_name, update) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [],
     [
       var(list_name),
       var(acc_name),
       {:fn, [], [{:->, [], [[var(head_name), var(acc_name)], update]}]}
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

  # ── pattern helpers ────────────────────────────────────────────────

  # Only the wrapped form: Sourceror's `literal_encoder` means a `[]` pattern
  # always arrives as `{:__block__, _, [[]]}`, never bare. A bare-`[]` clause sat
  # here and could not be reached by any input.
  defp empty_list_pattern?({:__block__, _, [[]]}), do: true
  defp empty_list_pattern?(_), do: false

  defp destructure_cons({:|, _, [head, tail]}), do: {:ok, head, tail}
  defp destructure_cons({:__block__, _, [[{:|, _, [head, tail]}]]}), do: {:ok, head, tail}
  defp destructure_cons(_), do: :error

  defp var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp var?(_), do: false

  defp returns_var?(body, pattern_param) do
    expr = body |> extract_do_body() |> unwrap_single()
    same_var?(expr, pattern_param)
  end

  defp extract_do_body(body) when is_list(body) do
    Enum.find_value(body, fn
      {{:__block__, _, [:do]}, expr} -> expr
      _ -> nil
    end)
  end

  defp extract_do_body(body), do: body

  defp unwrap_single({:__block__, _, [expr]}), do: expr
  defp unwrap_single(expr), do: expr

  defp same_var?({n, _, c1}, {n, _, c2})
       when is_atom(n) and (is_nil(c1) or is_atom(c1)) and (is_nil(c2) or is_atom(c2)),
       do: true

  defp same_var?(_, _), do: false

  defp build_issue(%{def_type: def_type, name: fn_name, arity: arity} = info) do
    %Issue{
      rule: :no_manual_list_reduce,
      message:
        "`#{def_type} #{fn_name}/#{arity}` is a manual recursive fold that " <>
          "reimplements `Enum.reduce/3`.\n\n" <>
          "Use `Enum.reduce(list, acc, fn elem, acc -> ... end)` instead — it is " <>
          "clearer and avoids unnecessary code.",
      meta: %{line: Map.get(info, :line)}
    }
  end
end
