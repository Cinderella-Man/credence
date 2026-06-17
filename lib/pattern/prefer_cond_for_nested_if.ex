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

  # Block-form constructs whose presence in a condition or body makes the
  # nested `if/else` unsafe to flatten by single-line text reassembly: they
  # render across multiple lines (or contain their own `->` clauses), which
  # would corrupt the generated `cond`. Excluding any nested `if` here also
  # guarantees flattenable nestings never overlap, so patches never collide.
  @block_forms [:if, :case, :cond, :with, :for, :fn, :receive, :try]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, clauses]} = node, acc when is_list(clauses) ->
          case flattenable_parts(condition, clauses) do
            {:ok, _parts} -> {node, [build_issue(meta) | acc]}
            :error -> {node, acc}
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
        {:if, _meta, [condition, clauses]} = node, acc when is_list(clauses) ->
          case build_patch(node, condition, clauses) do
            {:ok, patch} -> {node, [patch | acc]}
            :error -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  defp build_patch(if_node, condition, clauses) do
    with {:ok, {outer_cond, inner_cond, outer_do, inner_do, inner_else}} <-
           flattenable_parts(condition, clauses),
         %Sourceror.Range{} = outer_range <- Sourceror.get_range(if_node) do
      change =
        "cond do\n" <>
          "  #{render_expr(outer_cond)} -> #{render_expr(outer_do)}\n" <>
          "  #{render_expr(inner_cond)} -> #{render_expr(inner_do)}\n" <>
          "  true -> #{render_expr(inner_else)}\n" <>
          "end"

      {:ok, %{range: outer_range, change: change}}
    else
      _ -> :error
    end
  end

  # Returns the five parts of a *flattenable* nested `if/else` — an `if/else`
  # whose `else` body is itself an `if/else`, and where every condition and
  # body is a simple, single-line expression. Returns `:error` otherwise.
  # `check/2` and `fix_patches/2` both gate on this, so they agree exactly.
  defp flattenable_parts(condition, clauses) do
    outer_do = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    with true <- outer_do != nil,
         {:if, _, [inner_cond, inner_clauses]} when is_list(inner_clauses) <- else_body,
         inner_do = extract_clause(inner_clauses, :do),
         inner_else = extract_clause(inner_clauses, :else),
         true <- inner_do != nil,
         true <- inner_else != nil,
         parts = {condition, inner_cond, outer_do, inner_do, inner_else},
         true <- parts |> Tuple.to_list() |> Enum.all?(&simple?/1) do
      {:ok, parts}
    else
      _ -> :error
    end
  end

  # An expression is simple enough to move into a single `cond` clause line
  # when it contains no block-form construct and renders to a single line.
  defp simple?(ast), do: not contains_block_form?(ast) and single_line?(ast)

  defp single_line?(ast), do: not String.contains?(render_expr(ast), "\n")

  defp contains_block_form?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {form, _, _} = node, _acc when form in @block_forms -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  # Renders an AST expression to its source string.
  defp render_expr(ast) do
    ast
    |> Sourceror.to_string()
    |> String.trim()
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
