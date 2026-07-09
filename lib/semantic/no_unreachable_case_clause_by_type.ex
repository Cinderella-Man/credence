defmodule Credence.Semantic.NoUnreachableCaseClauseByType do
  @moduledoc """
  Removes unreachable case clauses that match atoms outside a function's return type.

  LLMs hallucinate atoms in `case` expressions matching function return values
  (e.g. `:dt` for `DateTime.compare/2` whose return type is `:eq | :gt | :lt`).
  The compiler warns:

      the following clause will never match:

          :dt

      because it attempts to match on the result of:

          DateTime.compare(due1, due2)

      which has type:

          dynamic(:eq or :gt or :lt)

  The fix removes the dead clause.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "the following clause will never match:"
  @match_suffix "because it attempts to match on the result of:"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_prefix) and
      String.contains?(msg, @match_suffix) and
      not String.contains?(msg, "__exception__: true")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_unreachable_case_clause_by_type,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) when is_binary(msg) do
    with {:ok, target_atom} <- extract_unreachable_atom(msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      new_ast = remove_dead_clause(ast, target_atom)
      if new_ast != ast, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # Extract the unreachable atom name from the compiler diagnostic message.
  # Message shape: "the following clause will never match:\n\n    :dt\n\nbecause …"
  defp extract_unreachable_atom(msg) do
    case Regex.run(~r/the following clause will never match:\n\n\s+:(\w+)\n\n/, msg) do
      [_, atom_name] -> {:ok, String.to_atom(atom_name)}
      _ -> :error
    end
  end

  # Walk the AST and remove every case clause whose pattern is the dead atom.
  defp remove_dead_clause(ast, target_atom) do
    Macro.prewalk(ast, fn
      {:case, case_meta, [subject, clauses_kw]} ->
        new_kw = remove_from_clauses(clauses_kw, target_atom)
        {:case, case_meta, [subject, new_kw]}

      node ->
        node
    end)
  end

  defp remove_from_clauses(clauses_kw, target_atom) do
    Enum.map(clauses_kw, fn
      {{:__block__, do_meta, [:do]}, clause_asts} ->
        filtered =
          Enum.reject(clause_asts, fn
            {:->, _meta, [[{:__block__, _, [atom]}], _body]} when is_atom(atom) ->
              atom == target_atom

            _ ->
              false
          end)

        {{:__block__, do_meta, [:do]}, filtered}

      other ->
        other
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
