defmodule Credence.Semantic.FixMapFetchNoneClause do
  @moduledoc """
  Repairs the LLM hallucination of `:none` in `case` clauses that match on
  `Map.fetch/2` results.

  LLMs consistently write `:none` instead of `:error` as the failure clause
  for `Map.fetch/2`, which causes a `CaseClauseError` at runtime since
  `Map.fetch/2` returns `:error`, never `:none`. The compiler may emit:

      "an expression is always required on the right side of ->.
       Please provide a value after ->"

  when the LLM writes a bare `:none ->` without a body, or a related
  diagnostic from the same anti-pattern.

  The fix rewrites `:none` to `:error` inside `case` expressions whose
  subject is a `Map.fetch/2` call:

      case Map.fetch(map, key) do
        :none -> ...          # before
        :error -> ...         # after
        {:ok, v} -> ...
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "an expression is always required on the right side of ->. Please provide a value after ->"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_map_fetch_none_clause,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:case, meta, [condition, clauses_block]} = node, false ->
            if map_fetch_call?(condition) do
              case replace_none_in_clauses(clauses_block) do
                {:ok, new_clauses} -> {{:case, meta, [condition, new_clauses]}, true}
                :error -> {node, false}
              end
            else
              {node, false}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp map_fetch_call?({{:., _, [{:__aliases__, _, [:Map]}, :fetch]}, _, _}), do: true
  defp map_fetch_call?(_), do: false

  defp replace_none_in_clauses([{{:__block__, do_meta, [:do]}, clause_asts}]) do
    {new_clauses, changed} =
      Enum.map_reduce(clause_asts, false, fn
        {:->, arrow_meta, [[{:__block__, pat_meta, [:none]}], body]}, _acc ->
          {{:->, arrow_meta, [[{:__block__, pat_meta, [:error]}], body]}, true}

        clause, acc ->
          {clause, acc}
      end)

    if changed do
      {:ok, [{{:__block__, do_meta, [:do]}, new_clauses}]}
    else
      :error
    end
  end

  defp replace_none_in_clauses(_), do: :error

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
