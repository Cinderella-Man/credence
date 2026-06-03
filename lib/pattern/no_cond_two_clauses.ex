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
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

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
    {:->, _, [[_true], else_body]} = second_clause

    if_clauses = build_if_clauses(original_kw, do_body, else_body)
    {:if, meta, [condition, if_clauses]}
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
    complement_operator?(op1, op2) and same_expr?(a, c) and same_expr?(b, d)
  end

  defp complementary_expressions?(_, _), do: false

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
