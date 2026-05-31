defmodule Credence.Pattern.NoIfTrueFalse do
  @moduledoc """
  Detects redundant `if/else` wrappers around boolean expressions.

  LLMs frequently emit this redundant boolean wrapper when the condition
  already evaluates to a boolean. An `if` whose `do` branch returns `true`
  and whose `else` branch returns `false` (or a wildcard default) is
  semantically identical to the condition itself.

  Also catches the generalised form where the `do` branch is a comparison
  or boolean operator (not just the literal `true`) and the `else` branch
  is `false` — these can be collapsed with `and`.

  ## Detected patterns

      if condition do true else false end
      if condition, do: true, else: false
      if condition do a == b else false end
      if condition do a and b else false end

  ## Bad

      if match?([_, _, _, _], parts) and Enum.all?(parts, &valid?/1) do
        true
      else
        false
      end

      if x > 0 do
        y == 1
      else
        false
      end

  ## Good

      match?([_, _, _, _], parts) and Enum.all?(parts, &valid?/1)

      x > 0 and y == 1

  ## Auto-fix

  - `if cond do true else false end` → `cond`
  - `if cond do expr else false end` → `cond and expr` (when `expr` is a
    comparison or boolean operator)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [_condition, clauses]} = node, acc when is_list(clauses) ->
          if redundant_boolean_if?(clauses) do
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

  # Classifies an if's clause list:
  #   :true_false — do: true, else: false  (replace with condition)
  #   :expr_false — do: <bool-expr>, else: false  (replace with condition and expr)
  #   :other      — not a redundant boolean if
  defp classify_if(clauses) when is_list(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    cond do
      normalize_bool(do_body) == true and normalize_bool(else_body) == false ->
        :true_false

      normalize_bool(else_body) == false and boolean_expr?(do_body) ->
        :expr_false

      true ->
        :other
    end
  end

  defp classify_if(_), do: :other

  defp redundant_boolean_if?(clauses), do: classify_if(clauses) != :other

  # Extracts the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  # Normalizes AST representations of boolean literals.
  defp normalize_bool(true), do: true
  defp normalize_bool(false), do: false
  defp normalize_bool({:__block__, _, [true]}), do: true
  defp normalize_bool({:__block__, _, [false]}), do: false
  defp normalize_bool(_), do: :other

  # Rewrites redundant boolean ifs to their collapsed form.
  defp maybe_rewrite({:if, _meta, [condition, clauses]} = node) when is_list(clauses) do
    case classify_if(clauses) do
      :true_false ->
        condition

      :expr_false ->
        do_body = extract_clause(clauses, :do)
        {:and, [], [condition, do_body]}

      :other ->
        node
    end
  end

  defp maybe_rewrite(node), do: node

  # Returns true when the expression is a comparison or boolean operator —
  # safe to use as a boolean in `cond and expr`.
  defp boolean_expr?({:__block__, _, [expr]}), do: boolean_expr?(expr)

  defp boolean_expr?({op, _, [_, _]})
       when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==, :and, :or],
       do: true

  defp boolean_expr?({:not, _, [_]}), do: true
  defp boolean_expr?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_if_true_false,
      message:
        "`if condition do <boolean> else false end` is redundant. " <>
          "Use the condition directly (or `condition and expr`) — both sides already return a boolean.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
