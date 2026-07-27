defmodule Credence.Pattern.FixMapFetchCaseMatch do
  @moduledoc """
  Detects `case Map.fetch(map, key)` clauses whose success pattern is a bare
  map or map-match — missing the `{:ok, ...}` tuple wrapper that `Map.fetch`
  actually returns — and wraps the pattern in `{:ok, ...}`.

  `Map.fetch/2` returns `{:ok, value} | :error`. LLMs frequently write the
  success clause as a bare map pattern (`%{fields} = val`) instead of the
  correct `{:ok, %{fields} = val}`. A bare map pattern never matches a tuple,
  so the clause is dead code and the `case` raises `CaseClauseError` on every
  successful fetch.

  ## Bad

      case Map.fetch(state, key) do
        :error ->
          Map.put(state, key, %{callers: [from]})

        %{callers: callers} = info ->
          Map.put(state, key, %{info | callers: [from | callers]})
      end

  ## Good

      case Map.fetch(state, key) do
        :error ->
          Map.put(state, key, %{callers: [from]})

        {:ok, %{callers: callers} = info} ->
          Map.put(state, key, %{info | callers: [from | callers]})
      end
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case node do
          {:case, case_meta, [subject, [{{:__block__, _, [:do]}, clauses}]]}
          when is_list(clauses) ->
            if map_fetch_call?(subject) do
              bad = Enum.filter(clauses, &bare_map_clause?/1)
              new_issues = Enum.map(bad, &build_issue(&1, case_meta))
              {node, Enum.reverse(new_issues) ++ acc}
            else
              {node, acc}
            end

          _ ->
            {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:case, case_meta, [subject, [{{:__block__, block_meta, [:do]}, clauses}]]} = node
      when is_list(clauses) ->
        if map_fetch_call?(subject) do
          new_clauses = Enum.map(clauses, &maybe_wrap_pattern/1)
          {:case, case_meta, [subject, [{{:__block__, block_meta, [:do]}, new_clauses}]]}
        else
          node
        end

      node ->
        node
    end)
  end

  # --- Detection helpers ---

  # True when `subject` is `Map.fetch(map, key)`.
  defp map_fetch_call?(
         {{:., _, [{:__aliases__, _, [:Map]}, :fetch]}, _, [_map, _key]}
       ),
       do: true

  defp map_fetch_call?(_), do: false

  # True when a case clause has a bare map or map-match pattern (not wrapped
  # in `{:ok, ...}` or any other tuple/atom).
  defp bare_map_clause?({:->, _, [[pattern], _body]}), do: bare_map_pattern?(pattern)
  defp bare_map_clause?(_), do: false

  # Bare `%{...}` map literal.
  defp bare_map_pattern?({:%{}, _, _}), do: true

  # `%{...} = var` map-match.
  defp bare_map_pattern?({:=, _, [{:%{}, _, _}, _]}), do: true

  defp bare_map_pattern?(_), do: false

  # Wrap a bare-map-pattern clause in `{:ok, pattern}`.
  defp maybe_wrap_pattern({:->, clause_meta, [[pattern], body]} = clause) do
    if bare_map_pattern?(pattern) do
      wrapped = {:__block__, [], [{{:__block__, [], [:ok]}, strip_meta(pattern)}]}
      {:->, clause_meta, [[wrapped], body]}
    else
      clause
    end
  end

  defp maybe_wrap_pattern(clause), do: clause

  # Strip line/column metadata so Sourceror renders the node cleanly.
  defp strip_meta(node) do
    Macro.prewalk(node, fn
      {form, meta, args} when is_list(meta) ->
        {form, Keyword.drop(meta, [:line, :column, :closing, :last, :end]), args}

      other ->
        other
    end)
  end

  defp build_issue({:->, clause_meta, _}, case_meta) do
    line = Keyword.get(clause_meta, :line) || Keyword.get(case_meta, :line)

    %Issue{
      rule: :fix_map_fetch_case_match,
      message:
        "Bare map pattern in `case Map.fetch` clause — `Map.fetch` returns " <>
          "`{:ok, value} | :error`, so a bare map pattern never matches. " <>
          "Wrap it in `{:ok, ...}`.",
      meta: %{line: line}
    }
  end
end
