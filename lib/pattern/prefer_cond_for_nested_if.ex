defmodule Credence.Pattern.PreferCondForNestedIf do
  @moduledoc """
  Detects nested `if/else` blocks where the `else` branch contains another `if`
  (with its own `else`), and flattens them into a `cond` for readability.

  ## Bad

      if x > 0 do
        "positive"
      else
        if x < 0 do
          "negative"
        else
          "zero"
        end
      end

  ## Good

      cond do
        x > 0 -> "positive"
        x < 0 -> "negative"
        true -> "zero"
      end

  ## Auto-fix

  Flattens the nested `if/else` into a single `cond` expression.
  The outer condition becomes the first clause, the inner condition
  becomes the second clause, and the inner `else` body becomes the
  catch-all `true` clause.

  ## Safety

  The transformation is behaviour-preserving: both forms evaluate
  conditions in the same top-to-bottom order, and both only evaluate
  the branch body for the first truthy condition. The `true` catch-all
  mirrors the inner `else`, which handles all remaining cases.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [_condition, clauses]} = node, acc when is_list(clauses) ->
          if nested_if_else?(clauses) do
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
  def fix_patches(ast, opts) do
    source = Keyword.fetch!(opts, :source)

    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {:if, _meta, [condition, clauses]} = node, acc when is_list(clauses) ->
          case try_build_patch(node, condition, clauses, source) do
            {:ok, patch} -> {node, [patch | acc]}
            :error -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  defp try_build_patch(if_node, outer_cond, clauses, _source) do
    outer_do = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    with true <- outer_do != nil,
         true <- else_body != nil,
         {:if, _, [inner_cond, inner_clauses]} <- else_body,
         true <- is_list(inner_clauses),
         inner_do = extract_clause(inner_clauses, :do),
         inner_else = extract_clause(inner_clauses, :else),
         true <- inner_do != nil,
         true <- inner_else != nil,
         %Sourceror.Range{} = outer_range <- Sourceror.get_range(if_node) do
      cond1_text = render_expr(outer_cond)
      cond2_text = render_expr(inner_cond)
      body1_text = render_expr(outer_do)
      body2_text = render_expr(inner_do)
      body3_text = render_expr(inner_else)

      change =
        "cond do\n" <>
          "  #{cond1_text} -> #{body1_text}\n" <>
          "  #{cond2_text} -> #{body2_text}\n" <>
          "  true -> #{body3_text}\n" <>
          "end"

      {:ok, %{range: outer_range, change: change}}
    else
      _ -> :error
    end
  end

  # Renders an AST expression to a single-line source string.
  defp render_expr(ast) do
    ast
    |> strip_position_meta()
    |> Sourceror.to_string()
    |> String.trim()
  end

  defp strip_position_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) ->
        {form,
         Keyword.drop(meta, [
           :line,
           :column,
           :closing,
           :last,
           :end,
           :do,
           :end_of_expression,
           :token,
           :delimiter,
           :newlines
         ]), args}

      other ->
        other
    end)
  end

  # True when the clause list is an if/else whose `else` body is itself
  # an if/else (i.e., the inner if also has an else branch).
  defp nested_if_else?(clauses) do
    case extract_clause(clauses, :else) do
      nil ->
        false

      {:if, _, [_, inner_clauses]} when is_list(inner_clauses) ->
        extract_clause(inner_clauses, :else) != nil

      _ ->
        false
    end
  end

  # Extracts the body for a given clause key (:do or :else).
  # Returns the body AST node, or nil.
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_cond_for_nested_if,
      message:
        "Nested `if/else` with an inner `if` in the else branch " <>
          "can be flattened into a `cond` for better readability.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
