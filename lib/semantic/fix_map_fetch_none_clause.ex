defmodule Credence.Semantic.FixMapFetchNoneClause do
  @moduledoc """
  Repairs the LLM hallucination of `:none` as the failure clause in `case`
  expressions over `Map.fetch/2`.

  `Map.fetch/2` returns `{:ok, value} | :error`, never `:none`. LLMs still
  write:

      case Map.fetch(map, key) do
        :none -> {:error, :not_found}
        {:ok, value} -> {:ok, value}
      end

  The `:none` clause is dead code, and every `:error` result raises
  `CaseClauseError`. Elixir's type checker flags exactly this shape:

      the following clause will never match:

          :none ->

      because it attempts to match on the result of:

          Map.fetch(map, key)

      which has type:

          dynamic(:error or {:ok, term()})

  The fix renames that `:none` pattern to `:error`, making the failure
  clause reachable as intended.

  ## Safety

  Renaming a dead clause makes it live, so it could steal `:error` results
  from a later clause that currently handles them (an explicit `:error`
  clause, a catch-all `_`, or a variable pattern) — that would change the
  answer of code that does not crash today. The rule therefore rewrites a
  `case` only when it contains exactly one bare `:none` clause and every
  other clause is a tuple pattern (`{:ok, ...}`, guarded or not), which
  provably cannot match the atom `:error`. Under that condition the fix
  only converts a certain `CaseClauseError` into the clause the author
  wrote for the failure path. All other shapes are left untouched, and
  `should_report?/2` keeps them unreported.

  ## Ordering

  `NoUnreachableCaseClauseByType` (501) claims the same
  `the following clause will never match` diagnostic and would *delete* the
  `:none` clause. This rule repairs it to `:error` instead, keeping the failure
  branch the author wrote, so it must win — which it does by declaration rather
  than by sorting before `N`, since the general rule declares 501.

  ## Bad

      defmodule CredenceNoneClauseE2eCheckFMFNC do
        def find(map, key) do
          case Map.fetch(map, key) do
            :none -> {:error, :not_found}
            {:ok, value} -> {:ok, value}
          end
        end
      end

  ## Good

      defmodule CredenceNoneClauseE2eCheckFMFNC do
        def find(map, key) do
          case Map.fetch(map, key) do
            :error -> {:error, :not_found}
            {:ok, value} -> {:ok, value}
          end
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "the following clause will never match") and
      String.contains?(msg, ":none ->") and
      String.contains?(msg, "Map.fetch(")
  end

  def match?(_), do: false

  @doc """
  Only report diagnostics this rule can actually fix. The matched message
  also fires for shapes the fix deliberately skips (an existing `:error`
  clause, a catch-all, a guarded or duplicated `:none`), which would
  otherwise be attributed to this rule without being repaired.
  """
  def should_report?(diagnostic, source) do
    fix(source, diagnostic) != source
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_map_fetch_none_clause,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    with target_line when is_integer(target_line) <- line(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:case, meta, [condition, clauses_block]} = node, false ->
            if map_fetch_call?(condition) do
              case replace_none_in_clauses(clauses_block, target_line) do
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

  defp map_fetch_call?({{:., _, [{:__aliases__, _, [:Map]}, :fetch]}, _, [_, _]}), do: true
  defp map_fetch_call?(_), do: false

  defp replace_none_in_clauses([{{:__block__, do_meta, [:do]}, clause_asts}], target_line)
       when is_list(clause_asts) do
    {none_clauses, other_clauses} = Enum.split_with(clause_asts, &none_clause?/1)

    if one_none_clause_on_line?(none_clauses, target_line) and
         Enum.all?(other_clauses, &tuple_clause?/1) do
      new_clauses = Enum.map(clause_asts, &rename_none_clause/1)
      {:ok, [{{:__block__, do_meta, [:do]}, new_clauses}]}
    else
      :error
    end
  end

  defp replace_none_in_clauses(_, _target_line), do: :error

  defp none_clause?({:->, _, [[{:__block__, _, [:none]}], _body]}), do: true
  defp none_clause?(_), do: false

  defp none_clause_line({:->, _, [[{:__block__, meta, [:none]}], _body]}), do: meta[:line]

  defp one_none_clause_on_line?([clause], target_line),
    do: none_clause_line(clause) == target_line

  defp one_none_clause_on_line?(_clauses, _target_line), do: false

  defp rename_none_clause({:->, arrow_meta, [[{:__block__, pat_meta, [:none]}], body]}) do
    {:->, arrow_meta, [[{:__block__, pat_meta, [:error]}], body]}
  end

  defp rename_none_clause(clause), do: clause

  # A clause whose pattern provably cannot match the atom :error — tuple
  # patterns only, optionally guarded.
  defp tuple_clause?({:->, _, [[pattern], _body]}), do: tuple_pattern?(pattern)
  defp tuple_clause?(_), do: false

  defp tuple_pattern?({:when, _, [pattern | _]}), do: tuple_pattern?(pattern)
  defp tuple_pattern?({:{}, _, _}), do: true

  defp tuple_pattern?({:__block__, _, [inner]}) do
    match?({:{}, _, _}, inner) or (is_tuple(inner) and tuple_size(inner) == 2)
  end

  defp tuple_pattern?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
