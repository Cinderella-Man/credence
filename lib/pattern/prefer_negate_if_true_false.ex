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

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, branches]} = node, acc ->
          if anti_pattern?(condition, branches) do
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
        {:if, _if_meta, [condition, branches]} = node, acc ->
          if anti_pattern?(condition, branches) do
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
    else_body = extract_clause(branches, :else)
    negated = {:!, [], [condition]}
    new_if = {:if, [], [negated, [do: else_body, else: false]]}

    %{
      range: Sourceror.get_range(node),
      change: Sourceror.to_string(new_if)
    }
  end

  # Returns true when the if matches: do branch is `false`, else branch exists.
  defp anti_pattern?(_condition, branches) when is_list(branches) do
    do_body = extract_clause(branches, :do)
    else_body = extract_clause(branches, :else)

    false_literal?(do_body) and else_body != nil
  end

  defp anti_pattern?(_, _), do: false

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
