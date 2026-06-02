defmodule Credence.Pattern.NoTautologicalIf do
  @moduledoc """
  Detects `if/else` expressions where both branches return the same value.

  When both the `do` and `else` branches produce identical code, the
  condition is irrelevant — the entire `if/else` can be replaced with
  the body of either branch.

  ## Detected patterns

      if condition do
        result
      else
        result
      end

      if swapped do
        result
      else
        result
      end

      if condition, do: value, else: value

  ## Good

      result

      value

  ## Auto-fix

  Replaces the entire `if/else` with the `do` branch body.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [_condition, clauses]} = node, acc when is_list(clauses) ->
          if tautological_if?(clauses) do
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
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:if, _meta, [_condition, clauses]} = node ->
        if tautological_if?(clauses) do
          extract_clause(clauses, :do)
        else
          node
        end

      node ->
        node
    end)
  end

  defp tautological_if?(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    do_body != nil and else_body != nil and ast_equal?(do_body, else_body)
  end

  # Extract the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  # Deep structural equality on AST, ignoring metadata (line numbers, etc.)
  defp ast_equal?(a, b) do
    strip_meta(a) == strip_meta(b)
  end

  defp strip_meta({form, _meta, args}) do
    {strip_meta(form), nil, strip_meta(args)}
  end

  defp strip_meta(list) when is_list(list), do: Enum.map(list, &strip_meta/1)
  defp strip_meta({a, b}), do: {strip_meta(a), strip_meta(b)}
  defp strip_meta(other), do: other

  defp build_issue(meta) do
    %Issue{
      rule: :no_tautological_if,
      message:
        "Both branches of this `if/else` return the same value. " <>
          "Replace the entire expression with the branch body.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
