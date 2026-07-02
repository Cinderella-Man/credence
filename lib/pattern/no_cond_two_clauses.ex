defmodule Credence.Pattern.NoCondTwoClauses do
  @moduledoc """
  Detects `cond` with exactly two clauses where the second guard is
  redundant — either literal `true` or the logical complement of the
  first guard. Both patterns are just an `if/else` in disguise.

  ## Bad

      cond do
        low > high -> false
        true ->
          mid = div(low + high, 2)
          search(mid, target)
      end

      cond do
        x <= target -> go_right
        x > target -> found
      end

  ## Good

      if low > high do
        false
      else
        mid = div(low + high, 2)
        search(mid, target)
      end

      if x <= target do
        go_right
      else
        found
      end

  ## Auto-fix

  Rewrites as `if/else` using the first clause's guard as the
  condition. The condition is never modified.

  For the complement case the rewrite is only applied when the guard's
  operands are plain variables or literals. A `cond`'s second guard is
  re-evaluated when the first is false, whereas the `if/else` evaluates the
  condition only once; restricting to side-effect-free, deterministic
  operands keeps the fix behaviour-preserving on every input.
  """

  use Credence.Pattern.Rule

  # DSL-unsafe in Ash.Expr only: converting a 2-clause `cond` to `if` drops the
  # complementary second guard, and under Ash's SQL 3-valued nil logic the two
  # forms differ when an operand is nil. (Ecto forbids `cond`; in Nx.Defn `if` is
  # exactly `cond ... true ->`, so it is equivalent there.)
  @impl true
  def unsafe_in_dsl, do: [:ash_expr]
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:cond, meta, _} = node, acc ->
          if two_clause_cond?(node) do
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
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
  end

  # Checks if a cond node has exactly 2 clauses with `true` as
  # the second guard.
  defp two_clause_cond?({:cond, _, [kw]}) when is_list(kw) do
    case extract_do_clauses(kw) do
      [first, second] -> guard_is_true?(second) or complementary_guards?(first, second)
      _ -> false
    end
  end

  defp two_clause_cond?(_), do: false

  # Extracts the list of arrow clauses from the cond's keyword args.
  defp extract_do_clauses(kw) do
    Enum.find_value(kw, fn
      {{:__block__, _, [:do]}, clauses} when is_list(clauses) -> clauses
      _ -> nil
    end)
  end

  # Checks if an arrow clause has `true` as its guard.
  defp guard_is_true?({:->, _, [[guard], _body]}) do
    match_true?(guard)
  end

  defp guard_is_true?(_), do: false

  defp match_true?(true), do: true
  defp match_true?({:__block__, _, [true]}), do: true
  defp match_true?(_), do: false

  defp maybe_rewrite({:cond, meta, [kw]} = node) when is_list(kw) do
    case extract_do_clauses(kw) do
      [first, second] ->
        if guard_is_true?(second) or complementary_guards?(first, second) do
          rewrite_to_if(meta, first, second, kw)
        else
          node
        end

      _ ->
        node
    end
  end

  defp maybe_rewrite(node), do: node

  # Builds an if/else node from the two cond clauses.
  defp rewrite_to_if(meta, first_clause, second_clause, original_kw) do
    {:->, _, [[condition], do_body]} = first_clause
    {:->, _, [[_guard], else_body]} = second_clause

    # Dropping the `->` clause wrappers loses any comment that sat on them
    # (e.g. a comment above a clause). Carry those onto the body that moves into
    # `do`/`else`. For the first clause the condition is reused as-is, so exclude
    # its comments to avoid duplicating them.
    do_body = carry_clause_comments(do_body, first_clause, [do_body, condition])
    else_body = carry_clause_comments(else_body, second_clause, [else_body])

    if_clauses = build_if_clauses(original_kw, do_body, else_body)
    {:if, meta, [condition, if_clauses]}
  end

  # Comments on `clause` that are not already carried by any node in `reused`,
  # attached to `body` as leading comments.
  defp carry_clause_comments(body, clause, reused) do
    reused_comments = Enum.flat_map(reused, &RuleHelpers.collect_comments/1)
    extra = RuleHelpers.collect_comments(clause) -- reused_comments
    RuleHelpers.carry_comments(body, extra, [])
  end

  # Builds the keyword list for the if node, reusing the original cond's
  # `:do` meta so the rendered output sits on the same source line.
  defp build_if_clauses(original_kw, do_body, else_body) do
    {{:__block__, do_meta, [:do]}, _} = hd(original_kw)

    [
      {{:__block__, do_meta, [:do]}, do_body},
      {{:__block__, do_meta, [:else]}, else_body}
    ]
  end

  # Checks if two clauses have complementary comparison guards.
  # e.g., `x <= y` and `x > y` — the second is always true when
  # the first is false.
  defp complementary_guards?({:->, _, [[g1], _]}, {:->, _, [[g2], _]}) do
    complementary_expressions?(g1, g2)
  end

  defp complementary_expressions?({:__block__, _, [g1]}, g2),
    do: complementary_expressions?(g1, g2)

  defp complementary_expressions?(g1, {:__block__, _, [g2]}),
    do: complementary_expressions?(g1, g2)

  defp complementary_expressions?({op1, _, [a, b]}, {op2, _, [c, d]}) do
    complement_operator?(op1, op2) and same_expr?(a, c) and same_expr?(b, d) and
      simple_operand?(a) and simple_operand?(b)
  end

  defp complementary_expressions?(_, _), do: false

  # A `cond`'s second guard is re-evaluated at runtime when the first is
  # false; an `if/else` evaluates the condition only once. The rewrite is
  # therefore only behaviour-preserving when the guard's operands carry no
  # side effects and are deterministic — i.e. plain variables or literals.
  # Function-call operands (which the comparison would re-run, possibly
  # observing different state) are deliberately left unflagged.
  defp simple_operand?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp simple_operand?(operand) when is_number(operand), do: true
  defp simple_operand?(operand) when is_atom(operand), do: true
  defp simple_operand?(operand) when is_binary(operand), do: true
  defp simple_operand?(_), do: false

  defp complement_operator?(:<=, :>), do: true
  defp complement_operator?(:<, :>=), do: true
  defp complement_operator?(:==, :!=), do: true
  defp complement_operator?(:>, :<=), do: true
  defp complement_operator?(:>=, :<), do: true
  defp complement_operator?(:!=, :==), do: true
  defp complement_operator?(_, _), do: false

  defp same_expr?(a, b), do: Macro.to_string(a) == Macro.to_string(b)

  defp build_issue(meta) do
    %Issue{
      rule: :no_cond_two_clauses,
      message:
        "`cond` with two clauses where the second guard is redundant " <>
          "(`true` or the complement of the first) is an `if/else` in disguise. " <>
          "Use `if/else` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
