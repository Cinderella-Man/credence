defmodule Credence.Pattern.NoCaseTupleGuardDispatch do
  @moduledoc """
  Detects `case` on a tuple of variables where every clause's pattern
  is the same tuple of the same variables — all dispatch is via guards.
  This is a `cond` in disguise.

  ## Bad

      case {e1, e2} do
        {e1, e2} when e1 < e2 -> advance_left(rest1, list2)
        {e1, e2} when e1 > e2 -> advance_right(list1, rest2)
        {e1, e2} -> advance_both(rest1, rest2)
      end

  ## Good

      cond do
        e1 < e2 -> advance_left(rest1, list2)
        e1 > e2 -> advance_right(list1, rest2)
        true -> advance_both(rest1, rest2)
      end

  ## Auto-fix

  Unwraps the tuple, extracts guards, and rewrites as `cond`.
  A trailing `_` wildcard is converted to `true`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:case, meta, _} = node, acc ->
          if guard_only_tuple_case?(node) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
  end

  # ── detection ────────────────────────────────────────────────────

  defp guard_only_tuple_case?({:case, _meta, [scrutinee, kw]}) when is_list(kw) do
    with {:ok, clauses} <- RuleHelpers.extract_do_body(kw),
         true <- is_list(clauses) and length(clauses) >= 2,
         vars when is_list(vars) <- tuple_vars(scrutinee) do
      has_guard = Enum.any?(clauses, &clause_has_guard?/1)
      has_guard and Enum.all?(clauses, &clause_ok?(&1, vars))
    else
      _ -> false
    end
  end

  defp guard_only_tuple_case?(_), do: false

  # Extract variable names from a tuple AST node.
  # Sourceror may wrap single expressions in __block__.
  defp tuple_vars({:__block__, _, [inner]}), do: tuple_vars(inner)

  defp tuple_vars({:{}, _, elems}) when is_list(elems) do
    names =
      for {name, _, ctx} <- elems, is_atom(name), is_atom(ctx) do
        name
      end

    if length(names) == length(elems), do: names, else: nil
  end

  # 2-element tuple uses {a, b} syntax (no :{} wrapper).
  defp tuple_vars({a, b}), do: tuple_vars({:{}, [], [a, b]})
  defp tuple_vars(_), do: nil

  defp clause_has_guard?({:->, _, [[{:when, _, _} | _], _]}), do: true
  defp clause_has_guard?(_), do: false

  defp clause_ok?({:->, _, [pattern_parts, _body]}, vars) do
    case pattern_parts do
      [{:when, _, [tuple_pat | _guard]}] -> tuple_matches?(tuple_pat, vars)
      [tuple_pat] -> tuple_matches?(tuple_pat, vars) or wildcard?(tuple_pat)
      _ -> false
    end
  end

  # Sourceror may wrap tuple patterns in __block__.
  defp tuple_matches?({:__block__, _, [inner]}, vars), do: tuple_matches?(inner, vars)

  defp tuple_matches?({:{}, _, elems}, vars) when is_list(elems) do
    names =
      for {name, _, ctx} <- elems, is_atom(name), is_atom(ctx) do
        name
      end

    names == vars
  end

  defp tuple_matches?({a, b}, vars), do: tuple_matches?({:{}, [], [a, b]}, vars)
  defp tuple_matches?(_, _), do: false

  defp wildcard?(:_), do: true
  defp wildcard?({:_, _, ctx}) when is_atom(ctx), do: true
  defp wildcard?(_), do: false

  # ── rewrite ──────────────────────────────────────────────────────

  defp maybe_rewrite({:case, case_meta, [_scrutinee, kw]} = node) when is_list(kw) do
    with {:ok, clauses} <- RuleHelpers.extract_do_body(kw),
         true <- is_list(clauses) and length(clauses) >= 2,
         vars when is_list(vars) <- tuple_vars_from_case(node) do
      has_guard = Enum.any?(clauses, &clause_has_guard?/1)

      if has_guard and Enum.all?(clauses, &clause_ok?(&1, vars)) do
        cond_clauses = Enum.map(clauses, &rewrite_clause/1)
        {:cond, case_meta, [RuleHelpers.replace_do_body(kw, cond_clauses)]}
      else
        node
      end
    else
      _ -> node
    end
  end

  defp maybe_rewrite(node), do: node

  # Extract vars from a case node's scrutinee.
  defp tuple_vars_from_case({:case, _meta, [scrutinee, _kw]}), do: tuple_vars(scrutinee)
  defp tuple_vars_from_case(_), do: nil

  # Rewrite a single case clause to a cond clause.
  defp rewrite_clause({:->, arrow_meta, [[{:when, _, [_tuple, guard]}], body]}) do
    {:->, arrow_meta, [[guard], body]}
  end

  defp rewrite_clause({:->, arrow_meta, [_pattern, body]}) do
    {:->, arrow_meta, [[true], body]}
  end

  # ── issue ────────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_case_tuple_guard_dispatch,
      message:
        "`case` on a tuple of variables where all dispatch is via guards " <>
          "is a `cond` in disguise. Use `cond` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
