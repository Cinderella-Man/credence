defmodule Credence.Pattern.NoIfBooleanResult do
  @moduledoc """
  Detects `if` expressions that return a boolean literal in one branch and an
  arbitrary expression in the other, which should use `or`/`and` instead.

  This catches residual patterns left by `NoCaseTrueFalse`, which converts
  `case bool_expr do true -> A; false -> B end` to `if bool_expr do A else B end`.
  When one branch is a boolean literal, the `if` can be simplified to a boolean
  operator.

  ## Detected patterns

      if cond do true else expr end    →    cond or expr
      if cond do expr else false end   →    cond and expr

  ## Bad

      if valid_ipv4?(host) do
        true
      else
        valid_domain?(host)
      end

  ## Good

      valid_ipv4?(host) or valid_domain?(host)

  ## Auto-fix

  Rewrites the `if` to use `or` or `and` as appropriate.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [_condition, clauses]} = node, acc when is_list(clauses) ->
          case classify_if(clauses) do
            :true_expr -> {node, [build_issue(meta, :or) | acc]}
            :expr_false -> {node, [build_issue(meta, :and) | acc]}
            _ -> {node, acc}
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

  # Classifies the if's clause list:
  #   :true_expr  — do: true, else: <non-boolean-expr>  (replace with cond or expr)
  #   :expr_false — do: <non-boolean-expr>, else: false  (replace with cond and expr)
  #   :other      — not this pattern
  defp classify_if(clauses) when is_list(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    cond do
      is_true_literal?(do_body) and not is_nil(else_body) and
          not is_boolean_literal?(else_body) ->
        :true_expr

      not is_nil(do_body) and not is_boolean_literal?(do_body) and
          is_false_literal?(else_body) ->
        :expr_false

      true ->
        :other
    end
  end

  defp classify_if(_), do: :other

  # Extracts the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  defp is_true_literal?(true), do: true
  defp is_true_literal?({:__block__, _, [true]}), do: true
  defp is_true_literal?(_), do: false

  defp is_false_literal?(false), do: true
  defp is_false_literal?({:__block__, _, [false]}), do: true
  defp is_false_literal?(_), do: false

  defp is_boolean_literal?(node), do: is_true_literal?(node) or is_false_literal?(node)

  # Postwalk callback: rewrite matching if nodes.
  defp maybe_rewrite({:if, _meta, [condition, clauses]} = node) when is_list(clauses) do
    case classify_if(clauses) do
      :true_expr ->
        else_body = extract_clause(clauses, :else)
        {:or, [], [condition, else_body]}

      :expr_false ->
        do_body = extract_clause(clauses, :do)
        {:and, [], [condition, do_body]}

      _ ->
        node
    end
  end

  defp maybe_rewrite(node), do: node

  defp build_issue(meta, operator) do
    %Issue{
      rule: :no_if_boolean_result,
      message:
        "`if` returning a boolean literal in one branch " <>
          "should use `#{operator}` operator instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
