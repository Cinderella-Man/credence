defmodule Credence.Semantic.NoUnreachableFunctionClause do
  @moduledoc """
  Fixes the compiler warning about unreachable function clauses.

  LLMs frequently emit duplicate function clauses when iterating on a solution
  (3 attempts all hitting the same pattern). The compiler warns:

      "this clause cannot match because a previous clause at line N matches the
       same pattern as this clause"

  With `--warnings-as-errors` this blocks compilation. The fix removes the
  unreachable later clause, preserving the first (reachable) one.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "this clause cannot match because a previous clause at line "

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_unreachable_function_clause,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: {clause_line, _col}}) when is_binary(msg) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      new_ast = remove_clause_at_line(ast, clause_line)
      if new_ast != ast, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # Walk the AST and remove the def/defp clause whose :line meta matches `target_line`.
  defp remove_clause_at_line(ast, target_line) do
    {new_ast, _changed} =
      Macro.prewalk(ast, false, fn
        # Match a block containing multiple statements (the module body)
        {:__block__, meta, statements}, acc ->
          filtered =
            Enum.reject(statements, fn
              {def_or_defp, clause_meta, _args}
              when def_or_defp in [:def, :defp] and is_list(clause_meta) ->
                Keyword.get(clause_meta, :line) == target_line

              _ ->
                false
            end)

          if length(filtered) < length(statements) do
            {{:__block__, meta, filtered}, true}
          else
            {{:__block__, meta, statements}, acc}
          end

        node, acc ->
          {node, acc}
      end)

    new_ast
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
