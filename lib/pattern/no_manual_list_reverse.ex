defmodule Credence.Pattern.NoManualListReverse do
  @moduledoc """
  Readability rule: Detects hand-rolled reimplementations of `Enum.reverse/1`.

  ## Why this matters

  When a function uses the classic tail-recursive accumulator pattern to
  reverse a list — building a new list by prepending each element to an
  accumulator and returning it on the empty-list base case — it is
  reimplementing `Enum.reverse/1` with no benefit.

  ## Bad

      defp do_reverse([], acc), do: acc
      defp do_reverse([head | tail], acc), do: do_reverse(tail, [head | acc])

  ## Good

      Enum.reverse(list)

  ## Detection scope

  Two-clause `defp` (or `def`) with arity 2 where:

  1. One clause matches `([], acc)` and returns `acc`
  2. The other clause matches `([head | tail], acc)` and recursively calls
     itself with `(tail, [head | acc])`
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

  defp extract_clause({def_type, meta, [{:when, _, [{fn_name, _, [p1, p2]}, _guard]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 2, def_type, meta, {p1, p2}, body, true}}
  end

  defp extract_clause({def_type, meta, [{fn_name, _, [p1, p2]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 2, def_type, meta, {p1, p2}, body, false}}
  end

  defp extract_clause(_), do: :error

  defp analyze_group(clauses) when length(clauses) != 2, do: []

  defp analyze_group([clause_a, clause_b]) do
    {name, _, def_type, _meta, _pats, _body, guarded_a} = clause_a
    {_, _, _, _, _, _, guarded_b} = clause_b

    # Skip if any clause has a guard — not a pure reverse pattern
    if guarded_a or guarded_b do
      []
    else
      cond do
        manual_reverse?(clause_a, clause_b, name) ->
          meta = elem(clause_a, 3)
          [build_issue(def_type, name, meta)]

        manual_reverse?(clause_b, clause_a, name) ->
          meta = elem(clause_b, 3)
          [build_issue(def_type, name, meta)]

        true ->
          []
      end
    end
  end

  # Check that one clause is the base case and the other is the recursive case.
  defp manual_reverse?(base_clause, recursive_clause, fn_name) do
    empty_list_acc_base?(base_clause) and
      cons_acc_recurse?(recursive_clause, fn_name)
  end

  # Base case: `([], acc), do: acc` — empty list returns the accumulator.
  defp empty_list_acc_base?({_name, 2, _def_type, _meta, {p1, p2}, body, _guarded}) do
    empty_list_pattern?(p1) and
      var?(p2) and
      returns_var?(body, p2)
  end

  # Recursive case: `([head | tail], acc), do: self(tail, [head | acc])`
  defp cons_acc_recurse?({_name, 2, _def_type, _meta, {p1, p2}, body, _guarded}, fn_name) do
    case destructure_cons(p1) do
      {:ok, head_var, tail_var} ->
        var?(p2) and
          recursive_call_prepend?(body, fn_name, tail_var, head_var, p2)

      :error ->
        false
    end
  end

  # Recognizes `[]` in a function parameter.
  defp empty_list_pattern?({:__block__, _, [[]]}), do: true
  defp empty_list_pattern?([]), do: true
  defp empty_list_pattern?(_), do: false

  # Recognizes `[head | tail]` in a function parameter.
  defp destructure_cons({:|, _, [head, tail]}), do: {:ok, head, tail}

  defp destructure_cons({:__block__, _, [[{:|, _, [head, tail]}]]}),
    do: {:ok, head, tail}

  defp destructure_cons(_), do: :error

  # Checks that a node is a simple variable.
  defp var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp var?(_), do: false

  # Checks that the body's last expression is just the given variable.
  defp returns_var?(body, pattern_param) do
    last = body |> extract_do_body() |> last_expression()
    same_var?(last, pattern_param)
  end

  # Checks that body calls `fn_name(tail_var, [head_var | acc_var])`.
  defp recursive_call_prepend?(body, fn_name, tail_param, head_param, acc_param) do
    case body |> extract_do_body() |> last_expression() do
      {^fn_name, _, [arg1, arg2]} ->
        same_var?(arg1, tail_param) and
          cons_append?(arg2, head_param, acc_param)

      _ ->
        false
    end
  end

  # Extracts the `do` body from a keyword list or returns the body as-is.
  defp extract_do_body(body) when is_list(body) do
    Enum.find_value(body, fn
      {{:__block__, _, [:do]}, expr} -> expr
      _ -> nil
    end)
  end

  defp extract_do_body(body), do: body

  # Checks `[head_var | acc_var]`.
  defp cons_append?({:|, _, [h, a]}, head_param, acc_param) do
    same_var?(h, head_param) and same_var?(a, acc_param)
  end

  # Sourceror may wrap: {:__block__, _, [[{:|, _, [h, a]}]]}
  defp cons_append?({:__block__, _, [[{:|, _, [h, a]}]]}, head_param, acc_param) do
    same_var?(h, head_param) and same_var?(a, acc_param)
  end

  defp cons_append?(_, _, _), do: false

  defp same_var?({n, _, _}, {n, _, _}) when is_atom(n), do: true
  defp same_var?(_, _), do: false

  defp last_expression({:__block__, _, exprs}) when is_list(exprs), do: List.last(exprs)
  defp last_expression(expr), do: expr

  defp build_issue(def_type, fn_name, meta) do
    %Issue{
      rule: :no_manual_list_reverse,
      message:
        "`#{def_type} #{fn_name}/2` is a manual tail-recursive reimplementation " <>
          "of `Enum.reverse/1`.\n\n" <>
          "Use `Enum.reverse(list)` instead — it is clearer and avoids unnecessary code.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
