defmodule Credence.Pattern.NoManualFind do
  @moduledoc """
  Detects hand-rolled recursive "find first matching element" functions that
  should use `Enum.find/3`.

  ## Why this matters

  The classic 3-clause recursive find — empty-list base returning a default,
  a guarded clause returning the head, a fallback clause recursing on the
  tail — reimplements `Enum.find/3` with no benefit:

      # Flagged (arity 1)
      defp find_odd([]), do: -1
      defp find_odd([h | _t]) when rem_safe(h), do: h
      defp find_odd([_h | t]), do: find_odd(t)

      # Flagged (arity 2)
      defp find_first([], default), do: default
      defp find_first([h | _t], _default) when h > 0, do: h
      defp find_first([_h | t], default), do: find_first(t, default)

  ## The fix

  Each flagged group collapses to a single clause delegating to `Enum.find/3`:

      defp find_first(list, default) when is_list(list),
        do: Enum.find(list, default, fn h -> h > 0 end)

  This is **behaviour-preserving for every input**:

  - **Domain.** The collapsed clause keeps the original name/arity and guards
    `when is_list(list)`. The multi-clause original only ever matched `[]` or
    `[_ | _]` (and raised `FunctionClauseError` otherwise). `is_list/1` is
    true for *both* proper and improper lists and false for everything else —
    exactly the original domain. Maps/ranges/scalars raise `FunctionClauseError`
    on both sides; an improper list whose match occurs before the improper tail
    returns the same element on both sides (verified), and one with no match
    raises `FunctionClauseError` on both sides.
  - **First match, same order.** Both walk a list head-to-tail and stop at the
    first element satisfying the predicate, returning that element (not the
    predicate's value — so a `nil`/`false` matched element is returned as-is,
    just like the original head clause).
  - **Default.** Returned only when nothing matches. See the narrowing below
    for why the default must be eager-evaluation-safe.

  ## Detection scope (only the safely-fixable cases)

  Exactly **3 clauses**, same name, all arity **1** or all arity **2**, where
  some assignment of the clauses fills these three roles:

  1. **Base** — `([])` (arity 1) / `([], default)` (arity 2), no guard, whose
     body is a *single expression*:
       - arity 1: a **literal** (number incl. negative, atom/`nil`/booleans,
         binary, `[]`);
       - arity 2: the **second parameter variable** returned unchanged.
  2. **Match** — `([h | _], …) when <guard>`, no other guard vars, body is
     *exactly* the head variable `h`.
  3. **Recurse** — `([_ | t], …)`, no guard, body is *exactly* the self-call
     on the tail (`fn(t)` / `fn(t, default)`), every other argument threaded
     through unchanged.

  ### Why these narrowings (each drops a different-answer case)

  - **Non-raising boolean guard only.** The `<guard>` must be a non-raising
    boolean: comparisons, `and`/`or`/`not`, and unary `is_*` checks over the
    head variable and literals. A guard that can raise (e.g. `rem(h, 2) != 0`
    on a non-integer) silently *skips* the element in the multi-clause form,
    but the same expression as an `Enum.find/3` predicate would *raise* — a
    different answer (verified). Such groups are left untouched.
  - **Eager-evaluation-safe default only.** An `Enum.find/3` default argument
    is evaluated *eagerly*, whereas the base clause runs *only* when the list
    is exhausted. A literal (arity 1) or an already-bound parameter (arity 2)
    has no side effect and the same value either way; an arbitrary expression
    default (e.g. `(IO.puts(...); -1)`) would run eagerly even when an element
    matches (verified) — not flagged.
  - **Single-expression bodies only.** Each role's body must be exactly its one
    expression (head var / self-call / default), never a multi-statement block.
    A block could carry a side effect that the predicate-based rewrite would
    drop or move — a different answer.
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

  # ── analysis ───────────────────────────────────────────────────────

  defp analyze([a, _, _] = clauses) do
    arity = elem(a, 1)

    if arity in [1, 2] and Enum.all?(clauses, fn c -> elem(c, 1) == arity end) do
      find_roles(clauses, arity)
    else
      :error
    end
  end

  defp analyze(_), do: :error

  defp find_roles([_, _, _] = clauses, arity) do
    fn_name = clauses |> hd() |> elem(0)

    Enum.find_value(permutations3(clauses), :error, fn {base, match, recurse} ->
      with {:ok, default_spec} <- base_role(base, arity),
           {:ok, head, guard} <- match_role(match, arity),
           true <- recurse_role(recurse, fn_name, arity),
           {:ok, info} <-
             build_clause(
               elem(match, 2),
               fn_name,
               arity,
               head,
               guard,
               default_spec,
               line_of(match)
             ) do
        {:ok, info}
      else
        _ -> nil
      end
    end)
  end

  defp permutations3([a, b, c]) do
    [{a, b, c}, {a, c, b}, {b, a, c}, {b, c, a}, {c, a, b}, {c, b, a}]
  end

  # Base: `([]), do: <literal>` (arity 1) — eager-eval-safe literal default.
  defp base_role({_n, 1, _dt, _m, {p1}, body, nil}, 1) do
    expr = extract_do_body(body)

    if empty_list_pattern?(p1) and literal_default?(expr) do
      {:ok, {:literal, expr}}
    else
      :error
    end
  end

  # Base: `([], default), do: default` (arity 2) — returns its own param2.
  defp base_role({_n, 2, _dt, _m, {p1, p2}, body, nil}, 2) do
    if empty_list_pattern?(p1) and var?(p2) and same_var?(extract_do_body(body), p2) do
      {:ok, {:param2, elem(p2, 0)}}
    else
      :error
    end
  end

  defp base_role(_, _), do: :error

  # Match: `([h | _], …) when <safe guard over h>, do: h`.
  defp match_role({_n, arity, _dt, _m, pats, body, guard}, arity)
       when arity in [1, 2] and not is_nil(guard) do
    with {:ok, head, _tail} <- destructure_cons(elem(pats, 0)),
         true <- var?(head),
         true <- same_var?(extract_do_body(body), head),
         true <- safe_guard?(guard),
         true <- guard_vars_subset?(guard, [elem(head, 0)]) do
      {:ok, head, guard}
    else
      _ -> :error
    end
  end

  defp match_role(_, _), do: :error

  # Recurse: `([_ | t], …), do: fn(t[, default])` — tail recursion, rest unchanged.
  defp recurse_role({_n, 1, _dt, _m, {p1}, body, nil}, fn_name, 1) do
    with {:ok, _head, tail} <- destructure_cons(p1),
         true <- var?(tail),
         {^fn_name, _, [arg]} <- extract_do_body(body),
         true <- same_var?(arg, tail) do
      true
    else
      _ -> false
    end
  end

  defp recurse_role({_n, 2, _dt, _m, {p1, p2}, body, nil}, fn_name, 2) do
    with {:ok, _head, tail} <- destructure_cons(p1),
         true <- var?(tail) and var?(p2),
         {^fn_name, _, [a1, a2]} <- extract_do_body(body),
         true <- same_var?(a1, tail) and same_var?(a2, p2) do
      true
    else
      _ -> false
    end
  end

  defp recurse_role(_, _, _), do: false

  # ── building the collapsed clause ──────────────────────────────────

  defp build_clause(def_type, fn_name, 1, head, guard, {:literal, default_expr}, line) do
    head_name = elem(head, 0)
    avoid = [head_name | collect_var_names(guard)]

    case fresh_list_var(avoid) do
      nil ->
        :error

      list_name ->
        body = find_body(default_expr, list_name, head_name, guard)

        {:ok,
         %{
           clause: make_def(def_type, fn_name, [var(list_name)], list_name, body),
           name: fn_name,
           arity: 1,
           def_type: def_type,
           line: line
         }}
    end
  end

  defp build_clause(def_type, fn_name, 2, head, guard, {:param2, dname}, line) do
    head_name = elem(head, 0)
    avoid = [head_name, dname | collect_var_names(guard)]

    case fresh_list_var(avoid) do
      nil ->
        :error

      list_name ->
        params = [var(list_name), var(dname)]
        body = find_body(var(dname), list_name, head_name, guard)

        {:ok,
         %{
           clause: make_def(def_type, fn_name, params, list_name, body),
           name: fn_name,
           arity: 2,
           def_type: def_type,
           line: line
         }}
    end
  end

  # `Enum.find(list, <default>, fn head -> <guard> end)`
  defp find_body(default_ast, list_name, head_name, guard) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :find]}, [],
     [
       var(list_name),
       default_ast,
       {:fn, [], [{:->, [], [[var(head_name)], guard]}]}
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

  # ── safe-guard classification ──────────────────────────────────────

  # A guard is "safe" iff it cannot raise and returns a boolean — so moving it
  # into an `Enum.find/3` predicate gives the same answer. Guards swallow raised
  # errors (skip the clause); a predicate would propagate them.
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

  defp guard_vars_subset?(guard, allowed) do
    Enum.all?(collect_var_names(guard), fn name -> name in allowed end)
  end

  # ── literal default ────────────────────────────────────────────────

  # Eager-evaluation-safe defaults: scalars (incl. negative numbers) and `[]`.
  defp literal_default?({:__block__, _, [[]]}), do: true

  defp literal_default?({:__block__, _, [v]}) when is_number(v) or is_atom(v) or is_binary(v),
    do: true

  defp literal_default?({:-, _, [{:__block__, _, [n]}]}) when is_number(n), do: true

  defp literal_default?(_), do: false

  # ── pattern helpers ────────────────────────────────────────────────

  defp empty_list_pattern?({:__block__, _, [[]]}), do: true
  defp empty_list_pattern?([]), do: true
  defp empty_list_pattern?(_), do: false

  defp destructure_cons({:|, _, [head, tail]}), do: {:ok, head, tail}
  defp destructure_cons({:__block__, _, [[{:|, _, [head, tail]}]]}), do: {:ok, head, tail}
  defp destructure_cons(_), do: :error

  defp var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp var?(_), do: false

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

  defp extract_do_body(body) when is_list(body) do
    Enum.find_value(body, fn
      {{:__block__, _, [:do]}, expr} -> expr
      _ -> nil
    end)
  end

  defp extract_do_body(body), do: body

  defp same_var?({n, _, c1}, {n, _, c2})
       when is_atom(n) and (is_nil(c1) or is_atom(c1)) and (is_nil(c2) or is_atom(c2)),
       do: true

  defp same_var?(_, _), do: false

  defp line_of(clause), do: clause |> elem(3) |> Keyword.get(:line)

  defp build_issue(%{def_type: def_type, name: fn_name, arity: arity} = info) do
    %Issue{
      rule: :no_manual_find,
      message:
        "`#{def_type} #{fn_name}/#{arity}` manually reimplements `Enum.find/3`.\n\n" <>
          "Use `Enum.find(list, default, predicate)` instead — it is clearer " <>
          "and avoids unnecessary code.",
      meta: %{line: Map.get(info, :line)}
    }
  end
end
