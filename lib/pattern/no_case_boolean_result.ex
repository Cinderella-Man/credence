defmodule Credence.Pattern.NoCaseBooleanResult do
  @moduledoc """
  Detects `case` expressions where both results are boolean literals but
  the patterns are non-boolean — a verbose atom-to-boolean conversion.

  When a `case` has exactly two clauses and both return `true`/`false`
  (in either order) while matching on non-boolean patterns, the expression
  could be replaced with a simpler boolean comparison.

  Note: this is the *inverse* of `no_case_true_false`, which catches
  `case bool_expr do true -> …; false -> … end`.  This rule catches
  `case expr do :ok -> true; :no -> false end`.

  ## Detected patterns

      case expr do
        :ok -> true
        :no -> false
      end

      case expr do
        :ok -> true
        _ -> false
      end

      expr |> case do
        :ok -> true
        :no -> false
      end

  ## Good

      expr == :ok
      match?(:ok, expr)

  ## Check-only

  No auto-fix because the rewrite depends on context and semantics may
  differ when `expr` returns an unexpected value (the `case` raises
  `CaseClauseError`, while a comparison returns `false`).
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # case expr do ... end
        {:case, meta, [_subject, kw]} = node, acc when is_list(kw) ->
          check_case_clauses(kw, node, acc, meta)

        # expr |> case do ... end
        {:case, meta, [kw]} = node, acc when is_list(kw) ->
          check_case_clauses(kw, node, acc, meta)

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp check_case_clauses(kw, node, acc, meta) do
    case extract_do_clauses(kw) do
      [clause_a, clause_b] ->
        pat_a = clause_pattern(clause_a)
        pat_b = clause_pattern(clause_b)

        if not boolean_pattern?(pat_a) and
             not boolean_pattern?(pat_b) and
             boolean_result_pair?(clause_body(clause_a), clause_body(clause_b)) do
          {node, [build_issue(meta) | acc]}
        else
          {node, acc}
        end

      _ ->
        {node, acc}
    end
  end

  # Extract the pattern from a case clause: {:->, _, [[pattern], body]}
  defp clause_pattern({:->, _, [[pattern], _body]}), do: pattern
  defp clause_pattern(_), do: :no_match

  # Extract the body from a case clause
  defp clause_body({:->, _, [[_pattern], body]}), do: body
  defp clause_body(_), do: :no_match

  # Check if a pattern is a boolean literal (handled by no_case_true_false)
  defp boolean_pattern?(true), do: true
  defp boolean_pattern?(false), do: true
  defp boolean_pattern?({:__block__, _, [true]}), do: true
  defp boolean_pattern?({:__block__, _, [false]}), do: true
  defp boolean_pattern?(_), do: false

  # Check if two clause bodies form an opposite boolean pair
  defp boolean_result_pair?(body_a, body_b) do
    case {unwrap_boolean(body_a), unwrap_boolean(body_b)} do
      {true, false} -> true
      {false, true} -> true
      _ -> false
    end
  end

  defp unwrap_boolean(true), do: true
  defp unwrap_boolean(false), do: false
  defp unwrap_boolean({:__block__, _, [true]}), do: true
  defp unwrap_boolean({:__block__, _, [false]}), do: false
  defp unwrap_boolean(_), do: :other

  defp extract_do_clauses([{{:__block__, _, [:do]}, clauses}]) when is_list(clauses),
    do: clauses

  defp extract_do_clauses(_), do: nil

  defp build_issue(meta) do
    %Issue{
      rule: :no_case_boolean_result,
      message:
        "`case` that converts non-boolean values to booleans " <>
          "could be replaced with a direct comparison or `match?/2`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
