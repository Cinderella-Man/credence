defmodule Credence.Semantic.PreferPatternMatchForNonEmptyList do
  @moduledoc """
  Fixes the compiler warning emitted when `length(var) > 0` is used in a
  `when` guard to check for a non-empty list.

  The Elixir compiler warns:

      do not use "length(items) > 0" to check if a list is not empty since
      length always traverses the whole list. Prefer to pattern match on a
      non-empty list, such as [_ | _], or use "items != []" as a guard

  The fix replaces the `when length(var) > 0` guard with a `[_ | _] = var`
  pattern match in the clause head, removing the `when` when it was the sole
  guard condition.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "do not use \"length("
  @match_suffix ") > 0\" to check if a list is not empty"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg) and String.contains?(msg, @match_suffix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_pattern_match_for_non_empty_list,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {:case, case_meta, [subject, clauses_kw]} ->
            new_kw = fix_case_clauses(clauses_kw)
            {:case, case_meta, [subject, new_kw]}

          node ->
            node
        end)

      if result == ast do
        source
      else
        Sourceror.to_string(result)
      end
    else
      _ -> source
    end
  end

  defp fix_case_clauses(clauses_kw) do
    Enum.map(clauses_kw, fn
      {{:__block__, do_meta, [:do]}, clauses} ->
        new_clauses = Enum.map(clauses, &fix_clause/1)
        {{:__block__, do_meta, [:do]}, new_clauses}

      other ->
        other
    end)
  end

  defp fix_clause({:->, arrow_meta, [[{:when, when_meta, [pattern, guard]}], body]}) do
    case extract_length_gt_zero(guard) do
      {:ok, var} ->
        new_pattern = {:=, [], [non_empty_list_pattern(), var]}
        {:->, arrow_meta, [[new_pattern], body]}

      :error ->
        {:->, arrow_meta, [[{:when, when_meta, [pattern, guard]}], body]}
    end
  end

  defp fix_clause(clause), do: clause

  # length(var) > 0
  defp extract_length_gt_zero({:>, _, [{:length, _, [var]}, zero]}) do
    with true <- simple_var?(var),
         0 <- extract_int(zero) do
      {:ok, var}
    else
      _ -> :error
    end
  end

  # 0 < length(var)
  defp extract_length_gt_zero({:<, _, [zero, {:length, _, [var]}]}) do
    with true <- simple_var?(var),
         0 <- extract_int(zero) do
      {:ok, var}
    else
      _ -> :error
    end
  end

  defp extract_length_gt_zero(_), do: :error

  defp extract_int({:__block__, _, [n]}) when is_integer(n), do: n
  defp extract_int(n) when is_integer(n), do: n
  defp extract_int(_), do: :error

  defp simple_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: true

  defp simple_var?(_), do: false

  # AST for [_ | _]
  defp non_empty_list_pattern do
    {:__block__, [],
     [
       [
         {:|, [],
          [
            {:_, [], nil},
            {:_, [], nil}
          ]}
       ]
     ]}
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
