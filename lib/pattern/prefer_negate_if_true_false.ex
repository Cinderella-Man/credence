defmodule Credence.Pattern.PreferNegateIfTrueFalse do
  @moduledoc """
  Detects `if cond do false else body end` and rewrites it to
  `if !cond do body else false end`.

  ## Why this matters

  The pattern `if cond do false else body end` is non-idiomatic Elixir.
  When the `do` branch is just `false`, negate the condition, swap the
  branches, and keep the explicit `false` in the else branch to preserve
  the boolean return type.

  ## Bad

      if MapSet.member?(seen, current) do
        false
      else
        MapSet.put(seen, current)
        |> loop(sum_of_squared_digits(current))
      end

  ## Good

      if !MapSet.member?(seen, current) do
        MapSet.put(seen, current)
        |> loop(sum_of_squared_digits(current))
      else
        false
      end

  ## Auto-fix

  Negates the condition and swaps the branches: moves the else body to
  the do branch, and places an explicit `false` in the else branch.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  # DSL-unsafe: introduces `!` to negate the condition. In Ash.Expr `!x` builds
  # `%Ash.Query.Call{name: :!}` (no SQL translation) rather than `not`'s
  # `%Ash.Query.Not{}`; in Nx.Defn `!` is reinterpreted. (Ecto would compile-error
  # on `!`, which the compile gate already reverts, so it is not listed.)
  @impl true
  def unsafe_in_dsl, do: [:ash_expr, :nx_defn]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, branches]} = node, acc ->
          if block_form?(meta) and anti_pattern?(condition, branches) do
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
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:if, if_meta, [condition, branches]} = node, acc ->
          if block_form?(if_meta) and anti_pattern?(condition, branches) do
            {node, [whole_node_patch(node, condition, branches) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Replace the whole `if` expression in one shot. Building the negated/swapped
  # `if` as AST and rendering it once avoids the fragile multi-range patch
  # arithmetic that previously dropped the closing paren of `!(cond)` whenever
  # the moved else-body was a multi-statement block. Elixir is not
  # indentation-sensitive, so `mix format` (run after the fix) restores layout.
  defp whole_node_patch(node, condition, branches) do
    # The do-branch IS `false`; reuse that node (rather than a fresh `false`) in
    # the swapped else position so any comment that sat on it is preserved. The
    # else-body is likewise reused. `render_replacement` strips stale positions
    # but keeps those of comment-bearing nodes; `line: 1` anchors them.
    do_false = extract_clause(branches, :do)
    else_body = extract_clause(branches, :else)
    negated = negate_condition(condition)
    new_if = {:if, [line: 1], [negated, [do: else_body, else: do_false]]}

    %{
      range: Sourceror.get_range(node),
      change: Credence.RuleHelpers.render_replacement(new_if, %{})
    }
  end

  # Negate comparison operators directly to avoid double-negatives like
  # `!(x != 0)`. Flip the operator instead of wrapping in `!`.
  defp negate_condition({:!=, meta, [left, right]}), do: {:==, meta, [left, right]}
  defp negate_condition({:==, meta, [left, right]}), do: {:!=, meta, [left, right]}
  defp negate_condition({:>, meta, [left, right]}), do: {:<=, meta, [left, right]}
  defp negate_condition({:<, meta, [left, right]}), do: {:>=, meta, [left, right]}
  defp negate_condition({:>=, meta, [left, right]}), do: {:<, meta, [left, right]}
  defp negate_condition({:<=, meta, [left, right]}), do: {:>, meta, [left, right]}
  # Default: wrap with !
  defp negate_condition(condition), do: {:!, [], [condition]}

  # Only block-form `if cond do … end` (which carries the `:do`/`:end` tokens in
  # its node metadata) is rewritten. A single-line keyword `if cond, do: …,
  # else: …` — especially inside string interpolation — would be corrupted by
  # rendering the swapped `if` as a multi-line block.
  defp block_form?(meta), do: Keyword.has_key?(meta, :do)

  # Returns true when the if matches: do branch is `false`, else branch exists,
  # and the case is NOT already handled by `no_if_true_false` (see below).
  defp anti_pattern?(condition, branches) when is_list(branches) do
    do_body = extract_clause(branches, :do)
    else_body = extract_clause(branches, :else)

    false_literal?(do_body) and else_body != nil and
      not handled_by_no_if_true_false?(condition, else_body)
  end

  defp anti_pattern?(_, _), do: false

  # `no_if_true_false` already collapses `if cond do false else <bool> end` to a
  # plain boolean expression (`not cond` / `not cond and <bool>`), but ONLY when
  # the condition is provably boolean. Stay out of that territory so the two
  # rules never both patch the same `if`. Our unique scope is therefore: a
  # non-boolean else body, or a condition that isn't provably boolean (e.g. the
  # `MapSet.member?/2` showcase) — exactly the cases where collapsing to a bare
  # boolean would be unsafe and only the negate-and-swap rewrite applies.
  defp handled_by_no_if_true_false?(condition, else_body) do
    condition_bool?(condition) and (true_literal?(else_body) or boolean_expr?(else_body))
  end

  defp true_literal?({:__block__, _, [true]}), do: true
  defp true_literal?(true), do: true
  defp true_literal?(_), do: false

  # Mirrors `Credence.Pattern.NoIfTrueFalse.condition_bool?/1`: conditions whose
  # result is always a boolean. Kept self-contained (small, rule-local copy).
  defp condition_bool?({:__block__, _, [expr]}), do: condition_bool?(expr)

  defp condition_bool?({op, _, [_, _]})
       when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==, :match?],
       do: true

  defp condition_bool?({op, _, [left, right]}) when op in [:and, :or],
    do: condition_bool?(left) and condition_bool?(right)

  defp condition_bool?({:not, _, [inner]}), do: condition_bool?(inner)
  defp condition_bool?({:is_nil, _, [_]}), do: true

  defp condition_bool?({{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _})
       when fun in [:all?, :any?, :empty?],
       do: true

  defp condition_bool?({:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _}]})
       when fun in [:all?, :any?, :empty?],
       do: true

  defp condition_bool?(_), do: false

  # Mirrors `Credence.Pattern.NoIfTrueFalse.boolean_expr?/1`.
  defp boolean_expr?({:__block__, _, [expr]}), do: boolean_expr?(expr)

  defp boolean_expr?({op, _, [_, _]})
       when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==, :and, :or, :match?],
       do: true

  defp boolean_expr?({:not, _, [_]}), do: true
  defp boolean_expr?({:is_nil, _, [_]}), do: true

  defp boolean_expr?({{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _})
       when fun in [:all?, :any?, :empty?],
       do: true

  defp boolean_expr?({:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _}]})
       when fun in [:all?, :any?, :empty?],
       do: true

  defp boolean_expr?(_), do: false

  # Check if a node is the literal `false`.
  defp false_literal?({:__block__, _, [false]}), do: true
  defp false_literal?(_), do: false

  # Extract the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_negate_if_true_false,
      message:
        "`if cond do false else body end` is non-idiomatic. " <>
          "Negate the condition: `if !cond do body else false end`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
