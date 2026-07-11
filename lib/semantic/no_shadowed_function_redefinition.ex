defmodule Credence.Semantic.NoShadowedFunctionRedefinition do
  @moduledoc """
  Fixes the compiler warning about shadowed function redefinitions.

  LLMs commonly define the same function twice with identical name/arity,
  separated by other code. The first definition is shadowed by the second,
  producing:

      "this clause cannot match because a previous clause at line N always matches"

  The existing `NoUnreachableFunctionClause` rule handles the "matches the same
  pattern" variant by removing the later unreachable clause. This rule handles
  the "always matches" variant — where the earlier clause's pattern is a
  catch-all that shadows a later redefinition — by removing the earlier shadowed
  definition and keeping the last (intended) one.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "this clause cannot match because a previous clause at line "
  @match_suffix " always matches"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.starts_with?(msg, @match_prefix) and String.ends_with?(msg, @match_suffix)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_shadowed_function_redefinition,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{message: msg}) when is_binary(msg) do
    with {:ok, earlier_line} <- parse_earlier_line(msg),
         {:ok, ast} <- Sourceror.parse_string(source) do
      new_ast = remove_clause_at_line(ast, earlier_line)
      if new_ast != ast, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # Extract the line number of the earlier (shadowed) clause from the message.
  defp parse_earlier_line(msg) do
    case Regex.run(
           ~r/^this clause cannot match because a previous clause at line (\d+) always matches$/,
           msg
         ) do
      [_, line_str] -> {:ok, String.to_integer(line_str)}
      _ -> :error
    end
  end

  # Walk the AST and remove the def/defp clause whose :line meta matches `target_line`.
  defp remove_clause_at_line(ast, target_line) do
    {new_ast, _changed} =
      Macro.prewalk(ast, false, fn
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
