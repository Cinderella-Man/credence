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

  ## Safety

  Wrapping a dead clause makes it live, so it may steal matches from a later
  clause that currently handles the `{:ok, value}` tuple (a catch-all variable,
  `_`, or another tuple pattern) — that would change the answer of code that
  does not crash today. The rule therefore fires only when every other clause
  in the `case` provably cannot match a two-tuple, which guarantees the fix
  only converts a certain `CaseClauseError` into the intended behaviour.
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
            if map_fetch_call?(subject) and safe_to_wrap?(clauses) do
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
        if map_fetch_call?(subject) and safe_to_wrap?(clauses) do
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
  defp map_fetch_call?({{:., _, [{:__aliases__, _, [:Map]}, :fetch]}, _, [_map, _key]}),
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

  # Wrapping is safe only when no other clause could match the `{:ok, value}`
  # tuple — otherwise the newly-live wrapped clause steals matches from it and
  # changes the answer of code that does not crash today.
  defp safe_to_wrap?(clauses) do
    Enum.all?(clauses, fn clause ->
      bare_map_clause?(clause) or clause_cannot_match_two_tuple?(clause)
    end)
  end

  # A guard can only restrict a pattern further, so the pattern alone decides.
  defp clause_cannot_match_two_tuple?({:->, _, [[{:when, _, [pattern | _]}], _body]}),
    do: cannot_match_two_tuple?(pattern)

  defp clause_cannot_match_two_tuple?({:->, _, [[pattern], _body]}),
    do: cannot_match_two_tuple?(pattern)

  defp clause_cannot_match_two_tuple?(_), do: false

  # Conservatively true only for patterns that can never match a two-tuple.
  # Sourceror wraps literals in `:__block__`.
  defp cannot_match_two_tuple?({:__block__, _, [literal]})
       when is_atom(literal) or is_number(literal) or is_binary(literal) or is_list(literal),
       do: true

  # A two-tuple tagged with an atom other than `:ok` cannot match `{:ok, _}`,
  # and `Map.fetch` returns no other tuple shape.
  defp cannot_match_two_tuple?({:__block__, _, [{first, _second}]}) do
    match?({:__block__, _, [tag]} when is_atom(tag) and tag != :ok, first)
  end

  defp cannot_match_two_tuple?({:%{}, _, _}), do: true
  defp cannot_match_two_tuple?({:%, _, _}), do: true
  # `{:{}, _, _}` is the AST of a tuple of size != 2.
  defp cannot_match_two_tuple?({:{}, _, _}), do: true
  defp cannot_match_two_tuple?({:<<>>, _, _}), do: true

  defp cannot_match_two_tuple?({:=, _, [left, right]}),
    do: cannot_match_two_tuple?(left) or cannot_match_two_tuple?(right)

  defp cannot_match_two_tuple?(_), do: false

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
