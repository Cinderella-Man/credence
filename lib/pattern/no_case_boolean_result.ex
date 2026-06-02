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

  ## Auto-fix (wildcard cases only)

  When one clause is a wildcard (`_`), the rewrite to `match?/2` is safe:

      case expr do :ok -> true; _ -> false end   →   match?(:ok, expr)
      case expr do :ok -> false; _ -> true end   →   not match?(:ok, expr)

  When both clauses have specific patterns (no wildcard), no auto-fix is
  provided — the `case` raises `CaseClauseError` on unexpected values while
  a comparison returns `false`, so semantics may differ.
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
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
  end

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

  # --- auto-fix: rewrite wildcard cases to match?/2 ---

  # case expr do ... end
  defp maybe_rewrite({:case, _meta, [subject, kw]} = node) when is_list(kw) do
    case extract_do_clauses(kw) do
      [clause_a, clause_b] ->
        case wildcard_rewrite(clause_a, clause_b, subject) do
          {:ok, replacement} -> replacement
          :skip -> node
        end

      _ ->
        node
    end
  end

  # expr |> case do ... end
  defp maybe_rewrite({:|>, _pipe_meta, [subject, {:case, _case_meta, [kw]}]} = node)
       when is_list(kw) do
    case extract_do_clauses(kw) do
      [clause_a, clause_b] ->
        case wildcard_rewrite(clause_a, clause_b, subject) do
          {:ok, replacement} -> replacement
          :skip -> node
        end

      _ ->
        node
    end
  end

  defp maybe_rewrite(node), do: node

  defp extract_clause({:->, _, [[pattern], body]}), do: {pattern, body}
  defp extract_clause(_), do: :error

  # Returns {:ok, match_expr} or :skip when a wildcard case can be rewritten.
  defp wildcard_rewrite(clause_a, clause_b, subject) do
    with {pat_a, body_a} <- extract_clause(clause_a),
         {pat_b, body_b} <- extract_clause(clause_b) do
      ua = normalize_pattern(pat_a)
      ub = normalize_pattern(pat_b)
      ba = unwrap_boolean(body_a)
      bb = unwrap_boolean(body_b)

      cond do
        # pattern -> true; _ -> false → match?(pattern, subject)
        ua == :other and ub == :wildcard and ba == true and bb == false and
          not variable_pattern?(pat_a) ->
          {:ok, {:match?, [], [strip_block(pat_a), subject]}}

        # pattern -> false; _ -> true → not match?(pattern, subject)
        ua == :other and ub == :wildcard and ba == false and bb == true and
          not variable_pattern?(pat_a) ->
          {:ok, {:not, [], [{:match?, [], [strip_block(pat_a), subject]}]}}

        # _ -> false; pattern -> true → match?(pattern, subject)
        ua == :wildcard and ub == :other and ba == false and bb == true and
          not variable_pattern?(pat_b) ->
          {:ok, {:match?, [], [strip_block(pat_b), subject]}}

        # _ -> true; pattern -> false → not match?(pattern, subject)
        ua == :wildcard and ub == :other and ba == true and bb == false and
          not variable_pattern?(pat_b) ->
          {:ok, {:not, [], [{:match?, [], [strip_block(pat_b), subject]}]}}

        true ->
          :skip
      end
    else
      _ -> :skip
    end
  end

  # A bare variable binding like `x` — not a useful match? pattern.
  defp variable_pattern?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp variable_pattern?(_), do: false

  # Strip Sourceror's {:__block__, _, [value]} wrapper for use in match?/2.
  defp strip_block({:__block__, _, [value]}), do: value
  defp strip_block(other), do: other

  defp normalize_pattern(true), do: :boolean
  defp normalize_pattern(false), do: :boolean
  defp normalize_pattern({:__block__, _, [true]}), do: :boolean
  defp normalize_pattern({:__block__, _, [false]}), do: :boolean
  defp normalize_pattern({:_, _, _}), do: :wildcard
  defp normalize_pattern(_), do: :other

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
