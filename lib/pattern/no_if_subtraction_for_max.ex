defmodule Credence.Pattern.NoIfSubtractionForMax do
  @moduledoc """
  Detects `if a > b, do: a - b, else: 0` (and `>=`) and rewrites to `max(0, a - b)`.

  LLMs frequently write this verbose conditional clamp instead of using
  `Kernel.max/2` directly. The `if` expression is semantically identical
  to `max(0, a - b)` and the function form is shorter and more idiomatic.

  ## Detected patterns

      if x > y, do: x - y, else: 0     →  max(0, x - y)
      if x >= y, do: x - y, else: 0    →  max(0, x - y)

  ## Bad

      water = if new_max_left > left_height, do: new_max_left - left_height, else: 0

  ## Good

      water = max(0, new_max_left - left_height)

  ## Auto-fix

  Replaces the `if` expression with `max(0, subtraction)`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, clauses]} = node, acc when is_list(clauses) ->
          if subtraction_clamp?(condition, clauses) do
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

  # ── Detection ──────────────────────────────────────────────────────

  defp subtraction_clamp?(condition, clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    case {condition, do_body, else_body} do
      {{:>, _, [left, right]}, {:-, _, [sub_left, sub_right]}, _} ->
        zero_literal?(else_body) and same_expr?(left, sub_left) and
          same_expr?(right, sub_right)

      {{:>=, _, [left, right]}, {:-, _, [sub_left, sub_right]}, _} ->
        zero_literal?(else_body) and same_expr?(left, sub_left) and
          same_expr?(right, sub_right)

      _ ->
        false
    end
  end

  defp zero_literal?(0), do: true
  defp zero_literal?({:__block__, _, [0]}), do: true
  defp zero_literal?(_), do: false

  # Compare two AST expressions for structural equality, ignoring metadata.
  defp same_expr?({name, _, ctx1}, {name, _, ctx2})
       when is_atom(name) and is_atom(ctx1) and is_atom(ctx2),
       do: true

  defp same_expr?({:__block__, _, [a]}, b), do: same_expr?(a, b)
  defp same_expr?(a, {:__block__, _, [b]}), do: same_expr?(a, b)
  defp same_expr?(a, b), do: Macro.to_string(a) == Macro.to_string(b)

  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      {^key, body} -> body
      _ -> nil
    end)
  end

  # ── Rewrite ────────────────────────────────────────────────────────

  defp maybe_rewrite({:if, _meta, [condition, clauses]} = node) when is_list(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    case {condition, do_body, else_body} do
      {{:>, _, [left, right]}, {:-, _, [sub_left, sub_right]}, _} ->
        if zero_literal?(else_body) and same_expr?(left, sub_left) and
             same_expr?(right, sub_right) do
          {:max, [], [0, do_body]}
        else
          node
        end

      {{:>=, _, [left, right]}, {:-, _, [sub_left, sub_right]}, _} ->
        if zero_literal?(else_body) and same_expr?(left, sub_left) and
             same_expr?(right, sub_right) do
          {:max, [], [0, do_body]}
        else
          node
        end

      _ ->
        node
    end
  end

  defp maybe_rewrite(node), do: node

  # ── Issue ──────────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :no_if_subtraction_for_max,
      message:
        "`if a > b, do: a - b, else: 0` can be simplified to `max(0, a - b)`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
