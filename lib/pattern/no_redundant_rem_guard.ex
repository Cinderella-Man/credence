defmodule Credence.Pattern.NoRedundantRemGuard do
  @moduledoc """
  Check-only rule: flags `rem(var, 2) == 1` (or `rem(var, 2) != 0`) guards
  when a preceding clause of the same function already handles the complementary
  `rem(var, 2) == 0`.

  ## Why this matters

  LLMs frequently add parity guards on the final clause of a multi-clause
  function even though clause ordering already guarantees the value.  When
  one clause handles `rem(x, 2) == 0` (even) and a later clause has
  `rem(x, 2) == 1` (odd), the second guard is always true for non-negative
  integers — `rem/2` with divisor 2 only produces 0 or 1 for `x >= 0`.

  ## Bad

      defp classify(x) when rem(x, 2) == 0, do: :even
      defp classify(x) when rem(x, 2) == 1, do: :odd

  ## Good

      defp classify(x) when rem(x, 2) == 0, do: :even
      defp classify(x), do: :odd

  ## Check-only

  Auto-fix is unsafe because the AST alone cannot prove the variable is
  non-negative.  For negative integers, `rem(x, 2)` returns -1 for odd
  values, so removing the guard could change behaviour.  Flag the issue
  and let the developer verify before removing.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    clauses = collect_guarded_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _, _, _} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # ── Clause collection ──────────────────────────────────────────

  defp collect_guarded_clauses(ast) do
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

  defp extract_clause(_), do: :error

  # ── Adjacent-pair analysis ─────────────────────────────────────

  defp analyze_group(clauses) when length(clauses) < 2, do: []

  defp analyze_group(clauses) do
    clauses
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [prev, curr] -> check_rem_pair(prev, curr) end)
  end

  defp check_rem_pair(
         {_name1, _arity1, prev_guard, _meta1, _def_type1},
         {_name2, _arity2, curr_guard, meta2, def_type2}
       ) do
    prev_rems = extract_rem_eq(prev_guard)
    curr_rems = extract_rem_all(curr_guard)

    Enum.flat_map(curr_rems, fn {var, val, op} ->
      if complementary?(prev_rems, var, val, op) do
        [build_issue(def_type2, var, val, op, meta2)]
      else
        []
      end
    end)
  end

  # ── Guard extraction helpers ───────────────────────────────────

  defp extract_rem_eq(guard) do
    guard
    |> flatten_conjuncts()
    |> Enum.flat_map(fn
      {:==, _, [{:rem, _, [var_ast, {:__block__, _, [2]}]}, val_ast]} ->
        with {:ok, var} <- unwrap_var(var_ast),
             {:ok, val} <- unwrap_int(val_ast) do
          [{var, val}]
        else
          _ -> []
        end

      _ ->
        []
    end)
  end

  defp extract_rem_all(guard) do
    guard
    |> flatten_conjuncts()
    |> Enum.flat_map(fn
      {:==, _, [{:rem, _, [var_ast, {:__block__, _, [2]}]}, val_ast]} ->
        with {:ok, var} <- unwrap_var(var_ast),
             {:ok, val} <- unwrap_int(val_ast) do
          [{var, val, :eq}]
        else
          _ -> []
        end

      {:!=, _, [{:rem, _, [var_ast, {:__block__, _, [2]}]}, val_ast]} ->
        with {:ok, var} <- unwrap_var(var_ast),
             {:ok, val} <- unwrap_int(val_ast) do
          [{var, val, :neq}]
        else
          _ -> []
        end

      _ ->
        []
    end)
  end

  defp unwrap_var({var, _, ctx}) when is_atom(var) and is_atom(ctx), do: {:ok, var}
  defp unwrap_var(_), do: :error

  defp unwrap_int({:__block__, _, [val]}) when is_integer(val), do: {:ok, val}
  defp unwrap_int(val) when is_integer(val), do: {:ok, val}
  defp unwrap_int(_), do: :error

  defp flatten_conjuncts({:and, _, [left, right]}),
    do: flatten_conjuncts(left) ++ flatten_conjuncts(right)

  defp flatten_conjuncts(other), do: [other]

  # ── Complement check ───────────────────────────────────────────

  # For modulus 2, 0 and 1 are complementary.
  # rem(x, 2) == 0 then rem(x, 2) == 1 → second is redundant
  # rem(x, 2) == 0 then rem(x, 2) != 0 → second is redundant
  defp complementary?(prev_rems, var, val, :eq) do
    complement = if val == 0, do: 1, else: 0
    Enum.any?(prev_rems, fn {pv, pval} -> pv == var and pval == complement end)
  end

  defp complementary?(prev_rems, var, val, :neq) do
    Enum.any?(prev_rems, fn {pv, pval} -> pv == var and pval == val end)
  end

  # ── Issue builder ──────────────────────────────────────────────

  defp build_issue(_def_type, var, val, op, meta) do
    guard_str = if op == :eq, do: "rem(#{var}, 2) == #{val}", else: "rem(#{var}, 2) != #{val}"
    complement = if val == 0, do: "1", else: "0"

    %Issue{
      rule: :no_redundant_rem_guard,
      message: """
      Redundant `when #{guard_str}` guard.
      A preceding clause already handles the complementary `rem(#{var}, 2) == #{complement}` \
      case, so for non-negative integers this guard is always true — it adds no safety \
      and can be removed.

      Note: verify that `#{var}` is non-negative before removing. For negative \
      integers, `rem(#{var}, 2)` can return -1, which neither `== 0` nor `== 1` matches.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
