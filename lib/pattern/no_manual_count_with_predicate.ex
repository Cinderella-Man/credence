defmodule Credence.Pattern.NoManualCountWithPredicate do
  @moduledoc """
  Detects hand-rolled recursive counting functions that should use `Enum.count/2`.

  ## Why this matters

  When a function counts list elements matching a predicate using manual
  tail-recursion with an accumulator, it is reimplementing `Enum.count/2`:

      # Flagged — manual recursive counting
      defp do_count([], _target, acc), do: acc
      defp do_count([h | t], target, acc) when h == target,
        do: do_count(t, target, acc + 1)
      defp do_count([_h | t], target, acc),
        do: do_count(t, target, acc)

      # Idiomatic — Enum.count/2
      Enum.count(list, &(&1 == target))

  ## Detection scope

  A group of exactly 3 clauses (all `def` or all `defp`) with arity 3
  where:

  1. One clause matches `([], _bound, acc)` and returns `acc`
  2. One clause matches `([head | tail], bound, acc)` with a **guard**
     on `head`/`bound` and recurses with `acc + 1` (or `1 + acc`)
  3. One clause matches `([_head | tail], bound, acc)` (no guard) and
     recurses with `acc` unchanged
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

  defp extract_clause({def_type, meta, [{:when, _, [{fn_name, _, [p1, p2, p3]}, _guard]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 3, def_type, meta, {p1, p2, p3}, body, true}}
  end

  defp extract_clause({def_type, meta, [{fn_name, _, [p1, p2, p3]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 3, def_type, meta, {p1, p2, p3}, body, false}}
  end

  defp extract_clause(_), do: :error

  defp analyze_group(clauses) when length(clauses) != 3, do: []

  defp analyze_group([a, b, c]) do
    {name, _, def_type, _meta, _pats, _body, _} = a

    permutations = [
      {a, b, c}, {a, c, b}, {b, a, c}, {b, c, a}, {c, a, b}, {c, b, a}
    ]

    Enum.find_value(permutations, [], fn {base, guarded, skip} ->
      if manual_count_pattern?(base, guarded, skip, name) do
        meta = elem(guarded, 3)
        [build_issue(def_type, name, meta)]
      end
    end)
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

  defp build_issue(def_type, fn_name, meta) do
    %Issue{
      rule: :no_manual_count_with_predicate,
      message:
        "`#{def_type} #{fn_name}/3` is a manual recursive counting function " <>
          "that reimplements `Enum.count/2`.\n\n" <>
          "Use `Enum.count(list, predicate)` instead — it is clearer " <>
          "and avoids unnecessary code.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
