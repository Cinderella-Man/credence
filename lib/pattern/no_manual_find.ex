defmodule Credence.Pattern.NoManualFind do
  @moduledoc """
  Readability rule: Detects hand-rolled reimplementations of `Enum.find/3`.

  ## Why this matters

  When a function uses the classic 3-clause recursive pattern to find the
  first element matching a predicate — base case returning a default,
  guarded clause returning the head, fallback clause recursing on the tail
  — it is reimplementing `Enum.find/3` with no benefit.

  ## Bad (arity 1)

      defp find_odd([]), do: -1
      defp find_odd([h | _t]) when rem(h, 2) != 0, do: h
      defp find_odd([_ | t]), do: find_odd(t)

  ## Bad (arity 2)

      defp find_first([], default), do: default
      defp find_first([h | _t], _default) when is_odd(h), do: h
      defp find_first([_ | t], default), do: find_first(t, default)

  ## Good

      Enum.find(list, -1, &(rem(&1, 2) != 0))

  ## Detection scope

  Three-clause `defp` (or `def`) where:

  **Arity 1:**
  1. One clause matches `([])` and returns a value (the default)
  2. One clause matches `([head | _tail])` with a guard and returns `head`
  3. One clause matches `([_ | tail])` and recurses with `tail`

  **Arity 2:**
  1. One clause matches `([], default)` and returns the default
  2. One clause matches `([head | _tail], _default)` with a guard and
     returns `head`
  3. One clause matches `([_ | tail], default)` and recurses with
     `(tail, default)`
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

  # ── Clause collection ──────────────────────────────────────────────────

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

  # Arity 1 with guard
  defp extract_clause(
         {def_type, meta, [{:when, _, [{fn_name, _, [p1]}, _guard]}, body]}
       )
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 1, def_type, meta, {p1}, body, true}}
  end

  # Arity 1 without guard
  defp extract_clause({def_type, meta, [{fn_name, _, [p1]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 1, def_type, meta, {p1}, body, false}}
  end

  # Arity 2 with guard
  defp extract_clause(
         {def_type, meta, [{:when, _, [{fn_name, _, [p1, p2]}, _guard]}, body]}
       )
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 2, def_type, meta, {p1, p2}, body, true}}
  end

  # Arity 2 without guard
  defp extract_clause({def_type, meta, [{fn_name, _, [p1, p2]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 2, def_type, meta, {p1, p2}, body, false}}
  end

  defp extract_clause(_), do: :error

  # ── Group analysis ─────────────────────────────────────────────────────

  # Need exactly 3 clauses to match the find-first pattern
  defp analyze_group(clauses) when length(clauses) != 3, do: []

  defp analyze_group(clauses) do
    {name, arity, def_type, _meta, _pats, _body, _guarded} = hd(clauses)

    if arity not in [1, 2] do
      []
    else
      # 1. Base case: empty list, no guard, body is not a recursive call
      base =
        Enum.find(clauses, fn {_n, _a, _d, _m, pats, body, guarded} ->
          not guarded and empty_list_head?(pats, arity) and
            not recursive_call?(body, name)
        end)

      # 2. Match case: cons with guard, returns the head variable
      match_clause =
        Enum.find(clauses, fn {_n, _a, _d, _m, pats, body, guarded} ->
          guarded and cons_head_returns_head?(pats, body, arity)
        end)

      # 3. Recurse case: cons without guard, recurses on tail
      recurse =
        Enum.find(clauses, fn {_n, _a, _d, _m, pats, body, guarded} = clause ->
          clause != base and clause != match_clause and
            not guarded and cons_tail_recurses?(pats, body, name, arity)
        end)

      if base != nil and match_clause != nil and recurse != nil do
        {_n, _a, _d, meta, _p, _b, _g} = match_clause
        [build_issue(def_type, name, arity, meta)]
      else
        []
      end
    end
  end

  # ── Pattern checks ─────────────────────────────────────────────────────

  # First pattern in the parameter tuple is an empty list
  defp empty_list_head?({p1}, 1), do: empty_list_pattern?(p1)
  defp empty_list_head?({p1, _p2}, 2), do: empty_list_pattern?(p1)
  defp empty_list_head?(_, _), do: false

  # Guarded cons clause returns the head variable
  defp cons_head_returns_head?({p1}, body, 1) do
    case destructure_cons(p1) do
      {:ok, head_var, _tail_var} -> returns_var?(body, head_var)
      :error -> false
    end
  end

  defp cons_head_returns_head?({p1, _p2}, body, 2) do
    case destructure_cons(p1) do
      {:ok, head_var, _tail_var} -> returns_var?(body, head_var)
      :error -> false
    end
  end

  defp cons_head_returns_head?(_, _, _), do: false

  # Unguarded cons clause recurses on tail
  defp cons_tail_recurses?({p1}, body, fn_name, 1) do
    case destructure_cons(p1) do
      {:ok, _head_var, tail_var} -> recursive_call_1?(body, fn_name, tail_var)
      :error -> false
    end
  end

  defp cons_tail_recurses?({p1, p2}, body, fn_name, 2) do
    case destructure_cons(p1) do
      {:ok, _head_var, tail_var} ->
        var?(p2) and recursive_call_2?(body, fn_name, tail_var, p2)

      :error ->
        false
    end
  end

  defp cons_tail_recurses?(_, _, _, _), do: false

  # ── AST helpers ────────────────────────────────────────────────────────

  defp empty_list_pattern?({:__block__, _, [[]]}), do: true
  defp empty_list_pattern?([]), do: true
  defp empty_list_pattern?(_), do: false

  defp destructure_cons({:|, _, [head, tail]}), do: {:ok, head, tail}

  defp destructure_cons({:__block__, _, [[{:|, _, [head, tail]}]]}),
    do: {:ok, head, tail}

  defp destructure_cons(_), do: :error

  defp var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp var?(_), do: false

  defp returns_var?(body, pattern_param) do
    last = body |> extract_do_body() |> last_expression()
    same_var?(last, pattern_param)
  end

  defp recursive_call?(body, fn_name) do
    case body |> extract_do_body() |> last_expression() do
      {^fn_name, _, _} -> true
      _ -> false
    end
  end

  defp recursive_call_1?(body, fn_name, tail_var) do
    case body |> extract_do_body() |> last_expression() do
      {^fn_name, _, [arg]} -> same_var?(arg, tail_var)
      _ -> false
    end
  end

  defp recursive_call_2?(body, fn_name, tail_var, default_var) do
    case body |> extract_do_body() |> last_expression() do
      {^fn_name, _, [arg1, arg2]} ->
        same_var?(arg1, tail_var) and same_var?(arg2, default_var)

      _ ->
        false
    end
  end

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
      rule: :no_manual_find,
      message:
        "`#{def_type} #{fn_name}/#{arity}` manually reimplements `Enum.find/3`.\n\n" <>
          "Consider using `Enum.find(list, default, &predicate)` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
