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
  A trailing `_` wildcard (or a final guardless tuple clause) is
  converted to `true`.

  ## Safety — why this is narrowed

  Moving a `when` guard into a `cond` condition is **not** generally
  behaviour-preserving:

    * Guards swallow errors: `when hd(a) > 0` treats a raised error as a
      failed clause, but the same expression as a `cond` condition
      propagates the error. So we only fire when every guard is built
      from operators that can never raise — the boolean connectives
      (`and`/`or`/`not`) over the total comparison operators
      (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`) whose operands are
      bare variables or literals. Term comparison is total, so these are
      bit-identical in a guard and in an expression, and they always
      yield a real boolean (so guard-truth and `cond`-truthiness agree).
    * A guard-only `case` with no catch-all raises `CaseClauseError`,
      while the corresponding `cond` raises `CondClauseError`. So we only
      fire when the final clause is a guardless catch-all (`_` or the
      full tuple), making both constructs total over the same inputs.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @comparison_ops [:==, :!=, :===, :!==, :<, :>, :<=, :>=]
  @boolean_ops [:and, :or]

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
         vars when is_list(vars) <- tuple_vars(scrutinee),
         {init, [last]} <- Enum.split(clauses, -1) do
      # Every clause but the last must be a full-tuple pattern with a
      # never-raising guard; the last must be a guardless catch-all.
      init != [] and
        Enum.all?(init, &guarded_clause_ok?(&1, vars)) and
        guardless_catchall?(last, vars)
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

  # A non-final clause: full-tuple pattern + exactly one never-raising guard.
  defp guarded_clause_ok?({:->, _, [[{:when, _, [tuple_pat, guard]}], _body]}, vars) do
    tuple_matches?(tuple_pat, vars) and safe_guard?(guard)
  end

  defp guarded_clause_ok?(_, _), do: false

  # The final clause: no guard, matches everything (full tuple or `_`).
  defp guardless_catchall?({:->, _, [[pattern], _body]}, vars) do
    not match?({:when, _, _}, pattern) and
      (tuple_matches?(pattern, vars) or wildcard?(pattern))
  end

  defp guardless_catchall?(_, _), do: false

  # A guard that cannot raise: boolean connectives over total comparisons
  # whose operands are bare variables or literals.
  defp safe_guard?({:__block__, _, [inner]}), do: safe_guard?(inner)

  defp safe_guard?({op, _, [l, r]}) when op in @boolean_ops do
    safe_guard?(l) and safe_guard?(r)
  end

  defp safe_guard?({:not, _, [x]}), do: safe_guard?(x)

  defp safe_guard?({op, _, [l, r]}) when op in @comparison_ops do
    safe_operand?(l) and safe_operand?(r)
  end

  defp safe_guard?(_), do: false

  # A comparison operand that, once evaluated, cannot itself raise:
  # a bare variable or a literal. Anything else (a call, arithmetic,
  # a constructed collection) is rejected.
  defp safe_operand?({:__block__, _, [v]}), do: literal?(v)
  defp safe_operand?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp safe_operand?(v), do: literal?(v)

  defp literal?(v), do: is_number(v) or is_atom(v) or is_binary(v)

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
    if guard_only_tuple_case?(node) do
      {:ok, clauses} = RuleHelpers.extract_do_body(kw)
      cond_clauses = Enum.map(clauses, &rewrite_clause/1)
      {:cond, case_meta, [RuleHelpers.replace_do_body(kw, cond_clauses)]}
    else
      node
    end
  end

  defp maybe_rewrite(node), do: node

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
