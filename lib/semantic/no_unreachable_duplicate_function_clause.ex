defmodule Credence.Semantic.NoUnreachableDuplicateFunctionClause do
  @moduledoc """
  Removes unreachable duplicate `def`/`defp` clauses sharing the same name and arity.

  LLMs frequently define the same function (especially `start_link/1`) twice in a
  module — once at the top as the public API and again later after adding helpers.
  The second clause can never match because the first always does, producing a
  "no match of right hand side value" diagnostic under warnings-as-errors.
  The fix removes the later unreachable duplicate clause, preserving the first.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "no match of right hand side value"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_unreachable_duplicate_function_clause,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      new_ast = remove_duplicate_clauses(ast)
      if new_ast != ast, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Walk the AST and remove def/defp clauses that share the same {type, name, arity}
  # key as an earlier clause in the same block — keeping only the first occurrence.
  defp remove_duplicate_clauses(ast) do
    {new_ast, _changed} =
      Macro.prewalk(ast, false, fn
        {:__block__, meta, statements}, acc ->
          {unique, _seen, changed} =
            Enum.reduce(statements, {[], MapSet.new(), false}, fn
              {def_type, _, _} = clause, {acc, seen, ch} when def_type in [:def, :defp] ->
                case clause_key(clause) do
                  nil ->
                    {acc ++ [clause], seen, ch}

                  key ->
                    if MapSet.member?(seen, key) do
                      {acc, seen, true}
                    else
                      {acc ++ [clause], MapSet.put(seen, key), ch}
                    end
                end

              other, {acc, seen, ch} ->
                {acc ++ [other], seen, ch}
            end)

          if changed do
            {{:__block__, meta, unique}, true}
          else
            {{:__block__, meta, statements}, acc}
          end

        node, acc ->
          {node, acc}
      end)

    new_ast
  end

  # Extract {type, name, arity} from a def/defp clause AST node.
  defp clause_key({def_type, _, [{name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(name) do
    arity =
      case args do
        list when is_list(list) -> length(list)
        nil -> 0
        _ -> nil
      end

    if arity != nil, do: {def_type, name, arity}
  end

  defp clause_key(_), do: nil

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
