defmodule Credence.Semantic.NoInGuardWithVariableRhs do
  @moduledoc """
  Fixes `x in variable` in guard expressions, which is a compile-time error.

  LLMs frequently write `value in variable` inside `when` guards, e.g.:

      [first | rest] when first == ?| or ?| in rest -> true

  The `in` macro requires a compile-time proper list or range on the right
  side, so `in rest` (a variable) raises:

      invalid right argument for operator "in", it expects a compile-time
      proper list or compile-time range on the right side when used in guard
      expressions, got: rest

  The fix removes the invalid `in variable` from the guard, adds a
  pattern-matching clause for the head case, and adds an `Enum.member?/2`
  fallback clause:

      [first | _rest] when first == ?| -> true
      [?| | _] -> true
      parts when is_list(parts) -> Enum.member?(parts, ?|)
      _ -> false
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "invalid right argument for operator \"in\""

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_in_guard_with_variable_rhs,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:case, case_meta, [subject, clauses_kw]}, acc ->
            case transform_case(clauses_kw, subject) do
              {:ok, new_kw} -> {{:case, case_meta, [subject, new_kw]}, true}
              :unchanged -> {{:case, case_meta, [subject, clauses_kw]}, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # ---- case-level transformation -------------------------------------------

  defp transform_case(clauses_kw, subject) do
    {new_kw, changed} =
      Enum.reduce(clauses_kw, {[], false}, fn
        {{:__block__, do_meta, [:do]}, clause_asts}, {acc, changed} ->
          {new_clauses, did_change} = process_clauses(clause_asts, subject)
          {acc ++ [{{:__block__, do_meta, [:do]}, new_clauses}], changed || did_change}

        other, {acc, changed} ->
          {acc ++ [other], changed}
      end)

    if changed, do: {:ok, new_kw}, else: :unchanged
  end

  # ---- clause-level transformation -----------------------------------------

  defp process_clauses(clauses, subject) do
    Enum.reduce(clauses, {[], false}, fn
      {:->, arrow_meta, [[{:when, when_meta, [pattern, guard]}], body]}, {acc, changed} ->
        case find_in_variable_rhs(guard) do
          nil ->
            {acc ++ [{:->, arrow_meta, [[{:when, when_meta, [pattern, guard]}], body]}], changed}

          {in_value, _in_var} ->
            remaining_guard = remove_in_from_guard(guard, in_value)

            new_clauses =
              build_replacement_clauses(
                pattern,
                remaining_guard,
                in_value,
                subject,
                body,
                arrow_meta
              )

            {acc ++ new_clauses, true}
        end

      clause, {acc, changed} ->
        {acc ++ [clause], changed}
    end)
  end

  # ---- find `in` with variable RHS -----------------------------------------

  # Direct: `value in variable`
  defp find_in_variable_rhs({:in, _, [lhs, {var, _, ctx}]})
       when is_atom(var) and (is_nil(ctx) or is_atom(ctx)) do
    {lhs, {var, [], nil}}
  end

  # Nested in `or`
  defp find_in_variable_rhs({:or, _, [left, right]}) do
    find_in_variable_rhs(left) || find_in_variable_rhs(right)
  end

  # Nested in `and`
  defp find_in_variable_rhs({:and, _, [left, right]}) do
    find_in_variable_rhs(left) || find_in_variable_rhs(right)
  end

  defp find_in_variable_rhs(_), do: nil

  # ---- remove `in` from guard ----------------------------------------------

  defp remove_in_from_guard({:or, _meta, [left, right]}, in_value) do
    cond do
      has_in?(left, in_value) -> right
      has_in?(right, in_value) -> left
      true -> nil
    end
  end

  defp remove_in_from_guard(_guard, _in_value), do: nil

  defp has_in?({:in, _, [lhs, _rhs]}, in_value), do: lhs == in_value
  defp has_in?(_, _), do: false

  # ---- build replacement clauses -------------------------------------------

  defp build_replacement_clauses(pattern, remaining_guard, in_value, subject, body, arrow_meta) do
    # Clause 1: original pattern with remaining guard (or no guard if `in` was
    # the entire guard expression)
    clause1 =
      case remaining_guard do
        nil ->
          # The `in variable` was the only guard — convert the `when` to a
          # plain pattern (drop the `when` wrapper entirely).
          {:->, arrow_meta, [[pattern], body]}

        guard ->
          {:->, arrow_meta, [[{:when, [], [pattern, guard]}], body]}
      end

    # Clause 2: pattern-match the value at the list head
    #   [in_value | _] -> body
    head_pattern = {:__block__, [], [[{:|, [], [in_value, {:_, [], nil}]}]]}
    clause2 = {:->, arrow_meta, [[head_pattern], body]}

    # Clause 3: Enum.member? fallback for the remaining list
    #   subject when is_list(subject) -> Enum.member?(subject, in_value)
    is_list_guard = {:is_list, [], [subject]}
    clause3_pattern = {:when, [], [subject, is_list_guard]}

    clause3_body =
      {{:., [], [{:__aliases__, [], [:Enum]}, :member?]}, [], [subject, in_value]}

    clause3 = {:->, arrow_meta, [[clause3_pattern], clause3_body]}

    [clause1, clause2, clause3]
  end

  # ---- helpers --------------------------------------------------------------

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
