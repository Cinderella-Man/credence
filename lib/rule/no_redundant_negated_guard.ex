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
      defp compare([h1 | _], [h2 | _]) when h1 != h2, do: h1

      # Idiomatic — clause ordering handles it
      defp compare([h1 | t1], [h1 | t2]), do: compare(t1, t2)
      defp compare([missing | _], _), do: missing

  ## Flagged patterns

  A function clause whose guard is `when a != b` or `when a !== b`,
  immediately preceded by a clause of the same function/arity with
  `when a == b` or `when a === b` (same variables, same positions).
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @equality_ops [:==, :===]
  @inequality_ops [:!=, :!==]

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _, _, _} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  # ------------------------------------------------------------
  # CLAUSE COLLECTION
  # ------------------------------------------------------------

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

  # Guarded form must come first
  defp extract_clause({def_type, meta, [{:when, _, [{fn_name, _, args}, guard]}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), guard, meta, def_type}}
  end

  defp extract_clause({def_type, _meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    # Unguarded clause — store nil guard
    {:ok, {fn_name, length(args), nil, nil, def_type}}
  end

  defp extract_clause(_), do: :error

  # ------------------------------------------------------------
  # GROUP ANALYSIS
  # ------------------------------------------------------------

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

  # ------------------------------------------------------------
  # GUARD EXTRACTION
  #
  # Extract a simple comparison from a guard expression.
  # Only matches bare comparisons (not compound guards with and/or).
  # ------------------------------------------------------------

  defp extract_comparison({op, _, [left, right]}, target_ops) when is_list(target_ops) do
    if op in target_ops do
      {:ok, op, left, right}
    else
      :error
    end
  end

  defp extract_comparison(_, _), do: :error

  # ------------------------------------------------------------
  # VARIABLE COMPARISON
  # ------------------------------------------------------------

  defp same_vars?({name1, _, ctx1}, {name2, _, ctx2})
       when is_atom(name1) and is_atom(name2) and is_atom(ctx1) and is_atom(ctx2) do
    name1 == name2
  end

  defp same_vars?(_, _), do: false

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

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
          #{def_type} foo([missing | _], _), do: missing
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
