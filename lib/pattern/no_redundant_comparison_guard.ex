defmodule Credence.Pattern.NoRedundantComparisonGuard do
  @moduledoc """
  Detects redundant comparison guards in multi-clause functions.

  When an earlier clause guards on `type(var) and var < literal`, a later
  clause's `type(var) and var >= literal` guard is always true for any
  value reaching it — the earlier clause already consumed the complementary
  domain. The same applies to `>`/`<=`, `<=`/`>`, `>=`/`<` pairs.

  This extends the concept from `NoRedundantNegatedGuard` (which handles
  `==`/`!=`) to comparison operators. Both clauses must carry the same
  type guard (e.g. `is_number/1`) so the comparison operates in a
  well-typed domain.

  ## Why this matters

  LLMs add "safety" comparison guards for the same reason they add
  negated guards — they don't trust Elixir's clause ordering.  When
  clause 1 already handles `n < 0`, clause 3's `n >= 0` is pure noise.

  ## Flagged patterns

  | Earlier clause                        | Later clause                          | Redundant part |
  | ------------------------------------- | ------------------------------------- | -------------- |
  | `when is_number(n) and n < 0`         | `when is_number(n) and n >= 0`        | `n >= 0`       |
  | `when is_number(n) and n > 0`         | `when is_number(n) and n <= 0`        | `n <= 0`       |
  | `when is_integer(n) and n <= 5`       | `when is_integer(n) and n > 5`        | `n > 5`        |

  ## Not flagged (safe)

  - Bare comparisons without a shared type guard (non-numeric terms
    would break the complement logic).
  - Different type guards across clauses.
  - Different variables or literals.

  ## Bad

      defmodule Bad do
        def f(n) when is_atom(n) and n < 0, do: :a
        def f(n) when is_atom(n) and n >= 0, do: :b
      end

  ## Good

      defmodule Bad do
        def f(n) when is_atom(n) and n < 0, do: :a
        def f(n) when is_atom(n), do: :b
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @complementary %{
    :< => :>=,
    :> => :<=,
    :<= => :>,
    :>= => :<
  }

  @type_guards [:is_number, :is_integer, :is_float, :is_binary, :is_bitstring, :is_atom]

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _, _, _, _} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  #
  # The fix removes ONLY the redundant comparison conjunct from the
  # flagged (later) clause's guard, keeping the type guard intact:
  #
  #     def f(n) when is_number(n) and n >= 0  →  def f(n) when is_number(n)
  #
  # Safety: any value reaching the flagged clause failed the earlier
  # complementary clause `is_X(n) and n COMP lit` (same type guard, same
  # var, same literal). For a value of type X, failing COMP means the
  # complementary comparison holds, so the comparison in this guard is
  # always true here — dropping it changes nothing. For a non-X value,
  # the retained type guard rejects identically. Term comparison is
  # total and never raises, so there are no edge cases. The earlier
  # clause is never touched (check flags only the later clause), so
  # check and fix agree exactly.
  @impl true
  def fix_patches(ast, _opts) do
    fixable_guards = collect_fixable_guards(ast)

    if fixable_guards == [] do
      []
    else
      RuleHelpers.patches_from_postwalk(ast, &apply_fix(&1, fixable_guards))
    end
  end

  # ── Clause collection ──────────────────────────────────────────

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
    case extract_comparison_info(guard) do
      {:ok, info} -> {:ok, {fn_name, length(args), info, meta, def_type, args}}
      :error -> {:ok, {fn_name, length(args), nil, meta, def_type, args}}
    end
  end

  defp extract_clause({def_type, meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), nil, meta, def_type, args}}
  end

  defp extract_clause(_), do: :error

  # ── Comparison extraction ──────────────────────────────────────

  defp extract_comparison_info(guard) do
    case guard do
      # Bare comparison: n < 0
      {op, _, [{var_name, _, ctx}, literal_ast]}
      when is_atom(var_name) and is_atom(ctx) ->
        literal = unwrap_literal(literal_ast)

        if is_number(literal) and op in Map.keys(@complementary) do
          {:ok, %{op: op, var: var_name, literal: literal, type_guard: nil}}
        else
          :error
        end

      # Bare comparison reversed: 0 < n
      {op, _, [literal_ast, {var_name, _, ctx}]}
      when is_atom(var_name) and is_atom(ctx) ->
        literal = unwrap_literal(literal_ast)
        reversed = reverse_op(op)

        if (is_number(literal) and reversed) && reversed in Map.keys(@complementary) do
          {:ok, %{op: reversed, var: var_name, literal: literal, type_guard: nil}}
        else
          :error
        end

      # Compound: type_guard(var) and comparison(var, literal)
      {:and, _, [left, right]} ->
        case try_extract_type_and_comparison(left, right) do
          {:ok, info} -> {:ok, info}
          :error -> try_extract_type_and_comparison(right, left)
        end

      _ ->
        :error
    end
  end

  # Sourceror wraps numeric literals in {:__block__, meta, [value]}.
  defp unwrap_literal({:__block__, _, [value]}), do: value
  defp unwrap_literal(value), do: value

  defp try_extract_type_and_comparison(type_side, comp_side) do
    with {:ok, type_var, type_guard} <- extract_type_guard(type_side),
         {:ok, info} <- extract_comparison_info(comp_side),
         true <- info.var == type_var do
      {:ok, %{info | type_guard: type_guard}}
    else
      _ -> :error
    end
  end

  defp extract_type_guard({guard_name, _, [{var_name, _, ctx}]})
       when guard_name in @type_guards and is_atom(var_name) and is_atom(ctx) do
    {:ok, var_name, guard_name}
  end

  defp extract_type_guard(_), do: :error

  defp reverse_op(:<), do: :>
  defp reverse_op(:>), do: :<
  defp reverse_op(:<=), do: :>=
  defp reverse_op(:>=), do: :<=
  defp reverse_op(_), do: nil

  # ── Analysis ───────────────────────────────────────────────────

  defp analyze_group(clauses) when length(clauses) < 2, do: []

  defp analyze_group(clauses) do
    clauses
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_name, _arity, info, meta, def_type, head}, idx} ->
      case info do
        nil ->
          []

        curr_info ->
          earlier = Enum.take(clauses, idx)

          case find_complementary_earlier(earlier, curr_info, head) do
            nil -> []
            _prev -> [build_issue(def_type, curr_info, meta)]
          end
      end
    end)
  end

  defp find_complementary_earlier(earlier_clauses, curr_info, curr_head) do
    Enum.find_value(earlier_clauses, fn {_n, _a, prev_info, _m, _d, prev_head} ->
      case prev_info do
        nil ->
          nil

        prev ->
          if complementary_ops?(prev.op, curr_info.op) and
               prev.var == curr_info.var and
               prev.literal == curr_info.literal and
               matching_type_guards?(prev.type_guard, curr_info.type_guard) and
               same_head?(prev_head, curr_head) do
            prev
          end
      end
    end)
  end

  defp complementary_ops?(op1, op2), do: Map.get(@complementary, op1) == op2

  # Both clauses must carry the same type guard. Bare comparisons (nil)
  # are NOT flagged — without a type guard the complement logic breaks
  # for non-numeric terms (atoms sort above numbers in Erlang).
  defp matching_type_guards?(nil, nil), do: false
  defp matching_type_guards?(g, g) when is_atom(g), do: true
  defp matching_type_guards?(_, _), do: false

  # ── Issue ──────────────────────────────────────────────────────

  defp build_issue(def_type, curr, meta) do
    op_str = Atom.to_string(curr.op)

    %Issue{
      rule: :no_redundant_comparison_guard,
      message: """
      Redundant `when ... #{op_str} #{curr.literal}` guard.
      An earlier clause already handles all values where the comparison \
      holds, so anything reaching this #{def_type} clause is guaranteed \
      to pass the guard. Remove the redundant comparison.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # ── Fix ────────────────────────────────────────────────────────

  defp collect_fixable_guards(ast) do
    ast
    |> collect_clauses_for_fix()
    |> Enum.group_by(fn {name, arity, _, _, _} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> fixable_in_group(group) end)
  end

  defp collect_clauses_for_fix(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_clause_with_guard(node) do
          {:ok, clause} -> {node, [clause | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(clauses)
  end

  defp extract_clause_with_guard(
         {def_type, _meta, [{:when, _, [{fn_name, _, args}, guard]}, _body]}
       )
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    info =
      case extract_comparison_info(guard) do
        {:ok, i} -> i
        :error -> nil
      end

    {:ok, {fn_name, length(args), info, guard, args}}
  end

  defp extract_clause_with_guard({def_type, _meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), nil, nil, args}}
  end

  defp extract_clause_with_guard(_), do: :error

  defp fixable_in_group(group) when length(group) < 2, do: []

  defp fixable_in_group(group) do
    group
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_n, _a, info, guard, head}, idx} ->
      case info do
        nil ->
          []

        curr_info ->
          earlier = Enum.take(group, idx)

          if complementary_earlier?(earlier, curr_info, head) do
            [guard]
          else
            []
          end
      end
    end)
  end

  defp complementary_earlier?(earlier, curr_info, curr_head) do
    Enum.any?(earlier, fn {_n, _a, prev_info, _g, prev_head} ->
      case prev_info do
        nil ->
          false

        prev ->
          complementary_ops?(prev.op, curr_info.op) and
            prev.var == curr_info.var and
            prev.literal == curr_info.literal and
            matching_type_guards?(prev.type_guard, curr_info.type_guard) and
            same_head?(prev_head, curr_head)
      end
    end)
  end

  # The earlier clause only consumes the complementary domain of inputs that
  # also reach the later clause when the two clauses match the SAME inputs apart
  # from the compared variable. A sufficient, safe condition is that their head
  # argument patterns are structurally identical (ignoring metadata). When they
  # differ (e.g. a `:neg_integer` type tag vs `:non_neg_integer`), the earlier
  # clause was skipped on the head — not failed on the guard — so the later
  # clause's comparison is NOT redundant.
  defp same_head?(head_a, head_b), do: strip_meta(head_a) == strip_meta(head_b)

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, _meta, args} -> {form, [], args}
      other -> other
    end)
  end

  defp apply_fix(node, fixable_guards) do
    case node do
      {def_type, meta, [{:when, when_meta, [head, guard]}, body]}
      when def_type in [:def, :defp] ->
        if guard in fixable_guards do
          {def_type, meta, [{:when, when_meta, [head, type_guard_side(guard)]}, body]}
        else
          node
        end

      _ ->
        node
    end
  end

  # A flagged guard is always `{:and, _, [a, b]}` with exactly one side a
  # type guard and the other the (redundant) comparison. Keep the type-guard
  # side.
  defp type_guard_side({:and, _, [left, right]}) do
    case extract_type_guard(left) do
      {:ok, _, _} -> left
      :error -> right
    end
  end
end
