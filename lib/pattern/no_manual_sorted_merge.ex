defmodule Credence.Pattern.NoManualSortedMerge do
  @moduledoc """
  Readability rule: Detects hand-rolled merge of two sorted lists.

  ## Why this matters

  When a function uses the classic merge-sort merge step — two base clauses
  for empty lists returning the other, and two recursive clauses comparing
  heads with a guard and consing the smaller onto a recursive call — it is
  reimplementing `Enum.sort/1` on the concatenation with no readability
  benefit.

  ## Bad

      defp merge([], list2), do: list2
      defp merge(list1, []), do: list1
      defp merge([h1 | t1], [h2 | _] = list2) when h1 <= h2 do
        [h1 | merge(t1, list2)]
      end
      defp merge(list1, [h2 | t2]) do
        [h2 | merge(list1, t2)]
      end

  ## Good

      Enum.sort(list1 ++ list2)

  ## Detection scope

  A function with arity 2 that has exactly 4 clauses:

  1. `([], x) -> x` — empty first list, return second
  2. `(x, []) -> x` — empty second list, return first
  3. `([h | t], x) when h <= head(x) -> [h | self(t, x)]` — cons smaller head
  4. `(x, [h | t]) -> [h | self(x, t)]` — cons remaining head

  The two recursive clauses must have complementary guards (one guarded,
  one not).
  """

  use Credence.Pattern.Rule

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _def_type, _meta, _pats, _body, _guarded} ->
      {name, arity}
    end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Collect all function clauses from the AST.
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

  # Extract a clause from a def/defp node.
  defp extract_clause({def_type, meta, [{:when, _, [{fn_name, _, [p1, p2]}, _guard]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 2, def_type, meta, {p1, p2}, body, true}}
  end

  defp extract_clause({def_type, meta, [{fn_name, _, [p1, p2]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 2, def_type, meta, {p1, p2}, body, false}}
  end

  defp extract_clause(_), do: :error

  # Only analyze groups with exactly 4 clauses.
  defp analyze_group(clauses) when length(clauses) != 4, do: []

  defp analyze_group(clauses) do
    {name, _, def_type, _meta, _, _, _} = hd(clauses)

    roles = Enum.map(clauses, &classify_clause(&1, name))

    has_empty_first = Enum.any?(roles, &(&1 == :empty_first))
    has_empty_second = Enum.any?(roles, &(&1 == :empty_second))
    has_guarded_merge = Enum.any?(roles, &(&1 == :guarded_merge))
    has_unguarded_merge = Enum.any?(roles, &(&1 == :unguarded_merge))

    if has_empty_first and has_empty_second and has_guarded_merge and has_unguarded_merge do
      # Find the guarded merge clause for its line number
      {_, _, _, meta, _, _, _} =
        Enum.find(clauses, fn clause -> classify_clause(clause, name) == :guarded_merge end)

      [build_issue(def_type, name, meta)]
    else
      []
    end
  end

  # Classify a clause by its role in the merge pattern.
  defp classify_clause({_name, 2, _def_type, _meta, {p1, p2}, body, guarded}, fn_name) do
    cond do
      not guarded and empty_list_pattern?(p1) and var?(p2) and returns_var?(body, p2) ->
        :empty_first

      not guarded and var?(p1) and empty_list_pattern?(p2) and returns_var?(body, p1) ->
        :empty_second

      guarded and guarded_merge_clause?(p1, p2, body, fn_name) ->
        :guarded_merge

      not guarded and unguarded_merge_clause?(p1, p2, body, fn_name) ->
        :unguarded_merge

      true ->
        :other
    end
  end

  # Recursive clause with guard: `([h | t], [h2 | _] = list2) when h <= h2 do [h | self(t, list2)]`
  defp guarded_merge_clause?(p1, p2, body, fn_name) do
    case destructure_cons(p1) do
      {:ok, head_var, tail_var} ->
        # p2 can be a cons pattern, a variable, or [h | t] = var
        second_param_ok? = var?(p2) or match?({:ok, _, _}, destructure_cons(p2))

        # For the body check, use the bound variable if p2 is an = pattern
        p2_for_body = extract_match_var(p2) || p2

        second_param_ok? and
          recursive_call_cons?(body, fn_name, tail_var, head_var, p2_for_body)

      :error ->
        false
    end
  end

  # Extract the variable from a `pattern = var` or `var = pattern` match.
  defp extract_match_var({:=, _, [left, right]}) do
    cond do
      var?(left) -> left
      var?(right) -> right
      true -> nil
    end
  end

  defp extract_match_var(_), do: nil

  # Unguarded recursive clause: `(list1, [h | t]) do [h | self(list1, t)]`
  defp unguarded_merge_clause?(p1, p2, body, fn_name) do
    case destructure_cons(p2) do
      {:ok, head_var, tail_var} ->
        var?(p1) and
          recursive_call_cons?(body, fn_name, p1, head_var, tail_var)

      :error ->
        false
    end
  end

  # Checks that body is `[head_var | self(arg1, arg2)]`.
  defp recursive_call_cons?(body, fn_name, arg1, head_var, arg2) do
    last = body |> extract_do_body() |> last_expression()

    case last do
      # Bare cons: `[h | self(a1, a2)]`
      {:|, _, [h, {^fn_name, _, [a1, a2]}]} ->
        same_var?(h, head_var) and same_var?(a1, arg1) and same_var?(a2, arg2)

      # List-wrapped cons (Sourceror renders `[h | t]` as `[{... | ...}]`)
      [{:|, _, [h, {^fn_name, _, [a1, a2]}]}] ->
        same_var?(h, head_var) and same_var?(a1, arg1) and same_var?(a2, arg2)

      # Block-wrapped
      {:__block__, _, [[{:|, _, [h, {^fn_name, _, [a1, a2]}]}]]} ->
        same_var?(h, head_var) and same_var?(a1, arg1) and same_var?(a2, arg2)

      _ ->
        false
    end
  end

  # Recognizes `[]` in a function parameter.
  defp empty_list_pattern?({:__block__, _, [[]]}), do: true
  defp empty_list_pattern?([]), do: true
  defp empty_list_pattern?(_), do: false

  # Recognizes `[head | tail]` in a function parameter.
  defp destructure_cons({:|, _, [head, tail]}), do: {:ok, head, tail}
  defp destructure_cons({:__block__, _, [[{:|, _, [head, tail]}]]}), do: {:ok, head, tail}
  # Also handle `[head | tail] = var` pattern — extract the cons part
  defp destructure_cons({:=, _, [{:|, _, [head, tail]}, _var]}), do: {:ok, head, tail}
  defp destructure_cons({:=, _, [_var, {:|, _, [head, tail]}]}), do: {:ok, head, tail}
  # Handle `[head | tail] = var` where cons is block-wrapped (Sourceror)
  defp destructure_cons({:=, _, [{:__block__, _, [[{:|, _, [head, tail]}]]}, _var]}),
    do: {:ok, head, tail}

  defp destructure_cons({:=, _, [_var, {:__block__, _, [[{:|, _, [head, tail]}]]}]}),
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

  # Extracts the `do` body from a keyword list or returns the body as-is.
  defp extract_do_body(body) when is_list(body) do
    Enum.find_value(body, fn
      {{:__block__, _, [:do]}, expr} -> expr
      _ -> nil
    end)
  end

  defp extract_do_body(body), do: body

  defp same_var?({n, _, _}, {n, _, _}) when is_atom(n), do: true
  defp same_var?(_, _), do: false

  defp last_expression({:__block__, _, exprs}) when is_list(exprs), do: List.last(exprs)
  defp last_expression(expr), do: expr

  defp build_issue(def_type, fn_name, meta) do
    %Issue{
      rule: :no_manual_sorted_merge,
      message:
        "`#{def_type} #{fn_name}/2` is a manual sorted merge of two lists.\n\n" <>
          "Use `Enum.sort(list1 ++ list2)` instead — it is clearer and avoids unnecessary code.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
