defmodule Credence.Rule.NoRedundantNegatedGuard do
  @moduledoc """
  Detects guard clauses that are logically redundant because a preceding
  clause of the same function already handles the complementary case.

  ## Why this matters
  LLMs add "safety" guards because they don't trust Elixir's clause
  ordering.  When a clause with `when a == b` precedes one with
  `when a != b`, the second guard is guaranteed to pass — anything
  reaching that clause already failed the equality check:

      # Flagged — second guard is redundant
      defp compare([h1 | t1], [h2 | t2]) when h1 == h2, do: compare(t1, t2)
      defp compare([h1 | _], [h2 |_ ]) when h1 != h2, do: h1

      # Idiomatic — clause ordering handles it
      defp compare([h1 | t1], [h1 | t2]), do: compare(t1, t2)
      defp compare([missing | _],_ ), do: missing

  ## Fix

  The fix removes the redundant negated guard from the second clause.
  Since the preceding clause already matches the equality case, the
  negated guard adds no value — the clause ordering already ensures
  that only unequal pairs reach the second clause.

  ## Flagged patterns

  A function clause whose guard is `when a != b` or `when a !== b`,
  immediately preceded by a clause of the same function/arity with
  `when a == b` or `when a === b` (same variables, same positions).
  """

  use Credence.Rule
  alias Credence.Issue

  @equality_ops [:==, :===]
  @inequality_ops [:!=, :!==]

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _, _, _} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)
    clauses = collect_clauses_for_fix(ast)
    fixable = find_fixable_clauses(clauses)

    if Enum.empty?(fixable) do
      source
    else
      ast
      |> Macro.prewalk(fn node -> apply_fix_if_needed(node, fixable) end)
      |> Sourceror.to_string()
    end
  end

  # ── CHECK helpers ──────────────────────────────────────────────

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

  defp extract_clause({def_type, meta, [{:when, _, [{fn_name, _, args}, guard]}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), guard, meta, def_type}}
  end

  defp extract_clause({def_type, _meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), nil, nil, def_type}}
  end

  defp extract_clause(_), do: :error

  defp analyze_group(clauses) when length(clauses) < 2, do: []

  defp analyze_group(clauses) do
    clauses
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [prev, curr] ->
      check_pair(prev, curr)
    end)
  end

  defp check_pair(
         {_name1, _arity1, prev_guard, _meta1, _def_type1},
         {_name2, _arity2, curr_guard, meta2, def_type2}
       ) do
    with {:ok, eq_op, eq_left, eq_right} <- extract_comparison(prev_guard, @equality_ops),
         {:ok, neq_op, neq_left, neq_right} <- extract_comparison(curr_guard, @inequality_ops),
         true <- same_vars?(eq_left, neq_left) and same_vars?(eq_right, neq_right) do
      [build_issue(def_type2, neq_op, eq_op, meta2)]
    else
      _ -> []
    end
  end

  # ── GUARD EXTRACTION ───────────────────────────────────────────

  defp extract_comparison(nil, _), do: :error

  defp extract_comparison({op, _, [left, right]}, target_ops) when is_list(target_ops) do
    if op in target_ops do
      {:ok, op, left, right}
    else
      :error
    end
  end

  defp extract_comparison(_, _), do: :error

  defp same_vars?({name1, _, ctx1}, {name2, _, ctx2})
       when is_atom(name1) and is_atom(name2) and is_atom(ctx1) and is_atom(ctx2) do
    name1 == name2
  end

  defp same_vars?(_, _), do: false

  defp build_issue(def_type, neq_op, eq_op, meta) do
    eq_str = if eq_op == :==, do: "==", else: "==="
    neq_str = if neq_op == :!=, do: "!=", else: "!=="

    %Issue{
      rule: :no_redundant_negated_guard,
      message: """
      Redundant `when ... #{neq_str} ...` guard.
      The preceding clause already matches `when ... #{eq_str} ...`, \
      so anything reaching this clause is guaranteed to have unequal \
      values. The guard adds no safety — remove it.

      Better yet, use pattern matching instead of guard equality \
      in the preceding clause, and drop this guard entirely:

          #{def_type} foo([val | t1], [val | t2]), do: ...
          #{def_type} foo([missing | _],_ ), do: missing
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # ── FIX helpers ────────────────────────────────────────────────
  #
  # The fix collects ALL guarded function clauses (both equality and
  # inequality), groups them by {name, arity}, finds adjacent pairs
  # where the first has an equality guard and the second has a matching
  # inequality guard (same variable *names*), and removes the redundant
  # inequality guard from the second clause during AST traversal.
  #
  # Key safety: we only remove a guard when:
  #   1. The preceding clause has an equality guard (== or ===)
  #   2. The current clause has an inequality guard (!= or !==)
  #   3. The variable names match across both clauses
  # ───────────────────────────────────────────────────────────────

  defp collect_clauses_for_fix(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_clause_fix(node) do
          {:ok, clause} -> {node, [clause | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(clauses)
  end

  defp extract_clause_fix(
         {def_type, _meta, [{:when, _when_meta, [{fn_name, _fn_meta, args}, guard]}, _body]}
       )
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    case extract_comparison(guard, @equality_ops ++ @inequality_ops) do
      {:ok, op, left, right} ->
        {:ok, {fn_name, length(args), def_type, guard, op, {left, right}}}

      :error ->
        :error
    end
  end

  defp extract_clause_fix(_), do: :error

  defp find_fixable_clauses(clauses) do
    clauses
    |> Enum.group_by(fn {name, arity, _, _, _, _} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} ->
      group
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [{_, _, _, _, op1, {l1, r1}}, {_, _, _, guard2, op2, {l2, r2}}] ->
        if op1 in @equality_ops and op2 in @inequality_ops and
             same_vars?(l1, l2) and same_vars?(r1, r2) do
          [guard2]
        else
          []
        end
      end)
    end)
  end

  defp apply_fix_if_needed(node, fixable) do
    case node do
      {def_type, meta, [{:when, _when_meta, [{fn_name, fn_meta, args}, guard]}, body]}
      when def_type in [:def, :defp] ->
        if guard in fixable do
          {def_type, meta, [{fn_name, fn_meta, args}, body]}
        else
          node
        end

      _ ->
        node
    end
  end
end
