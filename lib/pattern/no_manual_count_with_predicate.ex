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

      # Idiomatic — Enum.count/2
      Enum.count(list, &(&1 == target))

  ## Detection scope

  **3-clause guard pattern** — a group of exactly 3 clauses (all `def` or
  all `defp`) with the same name and arity where:

  1. One clause matches `([], ..., acc)` and returns `acc`
  2. One clause matches `([h | t], ..., acc)` with a **guard** on `h`/bound
     and recurses with `acc + 1` (or `1 + acc`)
  3. One clause matches `([_h | t], ..., acc)` (no guard) and recurses
     with `acc` unchanged

  **2-clause if pattern** — a group of exactly 2 clauses with the same
  name and arity where:

  1. One clause matches `([], ..., acc)` and returns `acc`
  2. One clause matches `([h | t], ..., acc)` whose body assigns
     `new_acc = if(condition, do: acc + 1, else: acc)` then recurses
     with `new_acc`
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _def_type, _meta, _patterns, _body, _guarded} ->
      {name, arity}
    end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp collect_clauses(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_clause(node) do
          {:ok, clause} -> {node, [clause | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(clauses)
  end

  defp extract_clause({def_type, meta, [{:when, _, [{fn_name, _, params}, _guard]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(params) do
    {:ok, {fn_name, length(params), def_type, meta, List.to_tuple(params), body, true}}
  end

  defp extract_clause({def_type, meta, [{fn_name, _, params}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(params) do
    {:ok, {fn_name, length(params), def_type, meta, List.to_tuple(params), body, false}}
  end

  defp extract_clause(_), do: :error

  # ── 3-clause guard pattern ─────────────────────────────────────────

  defp analyze_group([{_, 3, _, _, _, _, _} = a, b, c]) do
    {name, _, def_type, _meta, _pats, _body, _} = a

    permutations = [
      {a, b, c}, {a, c, b}, {b, a, c}, {b, c, a}, {c, a, b}, {c, b, a}
    ]

    Enum.find_value(permutations, [], fn {base, guarded, skip} ->
      if manual_count_pattern?(base, guarded, skip, name) do
        meta = elem(guarded, 3)
        [build_issue(def_type, name, 3, meta)]
      end
    end)
  end

  # 3-clause groups with non-3 arity — not a match for guard pattern
  defp analyze_group([_, _, _]), do: []

  # ── 2-clause if pattern ────────────────────────────────────────────

  defp analyze_group([{_, arity, _, _, _, _, _} = a, b]) when arity >= 2 do
    {name, _, def_type, _meta, _pats, _body, _} = a

    case find_if_count_pair(a, b, name) do
      {:ok, clause_meta} -> [build_issue(def_type, name, elem(a, 1), clause_meta)]
      :error -> []
    end
  end

  defp analyze_group(_), do: []

  defp manual_count_pattern?(base, guarded, skip, fn_name) do
    empty_acc_base?(base) and
      guarded_increment?(guarded, fn_name) and
      unguarded_skip?(skip, fn_name)
  end

  # Base case: `([], _bound, acc), do: acc` — empty list returns accumulator.
  defp empty_acc_base?({_name, 3, _def_type, _meta, {p1, _p2, p3}, body, guarded}) do
    not guarded and
      empty_list_pattern?(p1) and
      var?(p3) and
      returns_var?(body, p3)
  end

  # Guarded case: `([h | t], bound, acc) when <guard>, do: fn(t, bound, acc + 1)`
  defp guarded_increment?({_name, 3, _def_type, _meta, {p1, _p2, p3}, body, true}, fn_name) do
    case destructure_cons(p1) do
      {:ok, _head, tail_var} ->
        var?(p3) and
          recursive_call_increments?(body, fn_name, tail_var, p3)

      :error ->
        false
    end
  end

  defp guarded_increment?(_, _), do: false

  # Skip case: `([_h | t], bound, acc), do: fn(t, bound, acc)`
  defp unguarded_skip?({_name, 3, _def_type, _meta, {p1, _p2, p3}, body, false}, fn_name) do
    case destructure_cons(p1) do
      {:ok, _head, tail_var} ->
        var?(p3) and
          recursive_call_unchanged?(body, fn_name, tail_var, p3)

      :error ->
        false
    end
  end

  defp unguarded_skip?(_, _), do: false

  # ── 2-clause if pattern helpers ────────────────────────────────────

  defp find_if_count_pair(a, b, fn_name) do
    cond do
      if_count_base?(a) and if_count_recursive?(b, fn_name) ->
        {:ok, elem(b, 3)}

      if_count_base?(b) and if_count_recursive?(a, fn_name) ->
        {:ok, elem(a, 3)}

      true ->
        :error
    end
  end

  # Base case: empty list returns accumulator (any arity, any position).
  defp if_count_base?({_name, _arity, _def_type, _meta, patterns, body, guarded}) do
    not guarded and
      has_empty_list_param?(patterns) and
      last_param_returned?(patterns, body)
  end

  defp has_empty_list_param?(patterns) do
    # Check all positions except the last (which is the accumulator)
    Enum.any?(0..(tuple_size(patterns) - 2), fn i ->
      empty_list_pattern?(elem(patterns, i))
    end)
  end

  # Recursive case: cons pattern with `if` conditional increment.
  defp if_count_recursive?({_name, _arity, _def_type, _meta, patterns, body, false}, fn_name) do
    arity = tuple_size(patterns)

    has_cons =
      Enum.any?(0..(arity - 1), fn i ->
        match?({:ok, _, _}, destructure_cons(elem(patterns, i)))
      end)

    acc = elem(patterns, arity - 1)
    has_cons and var?(acc) and body_has_if_increment?(body, fn_name, acc)
  end

  defp if_count_recursive?(_, _), do: false

  defp last_param_returned?(patterns, body) do
    last = elem(patterns, tuple_size(patterns) - 1)
    var?(last) and returns_var?(body, last)
  end

  # Body must be: `new_acc = if(cond, do: acc + 1, else: acc)` followed by
  # a recursive call `fn_name(..., new_acc)`.
  defp body_has_if_increment?(body, fn_name, acc_param) do
    case body |> extract_do_body() do
      {:__block__, _, [assign, call]} ->
        if_assign_increment?(assign, acc_param) and
          call_with_var?(call, fn_name, assigned_var(assign))

      _ ->
        false
    end
  end

  defp if_assign_increment?({:=, _, [var, if_expr]}, acc_param) do
    var?(var) and if_increments_acc?(if_expr, acc_param)
  end

  defp if_assign_increment?(_, _), do: false

  defp assigned_var({:=, _, [var, _]}), do: var

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

  defp call_with_var?({name, _, args}, fn_name, var) when is_list(args) and name == fn_name do
    Enum.any?(args, &same_var?(&1, var))
  end

  defp call_with_var?(_, _, _), do: false

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

  # Checks body is `fn_name(tail, bound, acc + 1)` or `fn_name(tail, bound, 1 + acc)`
  defp recursive_call_increments?(body, fn_name, tail_param, acc_param) do
    case body |> extract_do_body() |> last_expression() do
      {^fn_name, _, [arg1, _arg2, add_expr]} ->
        same_var?(arg1, tail_param) and increment_by_one?(add_expr, acc_param)

      _ ->
        false
    end
  end

  # Checks body is `fn_name(tail, bound, acc)` — acc unchanged
  defp recursive_call_unchanged?(body, fn_name, tail_param, acc_param) do
    case body |> extract_do_body() |> last_expression() do
      {^fn_name, _, [arg1, _arg2, arg3]} ->
        same_var?(arg1, tail_param) and same_var?(arg3, acc_param)

      _ ->
        false
    end
  end

  # Checks expression is `acc + 1` or `1 + acc` (Sourceror wraps literals in :__block__)
  defp increment_by_one?({:+, _, [left, right]}, acc_param) do
    (literal_one?(left) and acc_var?(right, acc_param)) or
      (acc_var?(left, acc_param) and literal_one?(right))
  end

  defp increment_by_one?(_, _), do: false

  defp literal_one?(1), do: true
  defp literal_one?({:__block__, _, [1]}), do: true
  defp literal_one?(_), do: false

  defp acc_var?({name, _, ctx}, {name, _, _}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: true

  defp acc_var?(_, _), do: false

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

  defp build_issue(def_type, fn_name, arity, meta) do
    %Issue{
      rule: :no_manual_count_with_predicate,
      message:
        "`#{def_type} #{fn_name}/#{arity}` is a manual recursive counting function " <>
          "that reimplements `Enum.count/2`.\n\n" <>
          "Use `Enum.count(list, predicate)` instead — it is clearer " <>
          "and avoids unnecessary code.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
