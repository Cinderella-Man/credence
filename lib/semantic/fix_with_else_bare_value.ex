defmodule Credence.Semantic.FixWithElseBareValue do
  @moduledoc """
  Fixes bare values in `else` clauses of `with` expressions.

  LLMs commonly write `with ... else bare_value end` forgetting that `else`
  requires `pattern -> body` clauses.  The compiler rejects this with:

      "expected -> clauses for :else in \"with\""

  The fix wraps each bare expression in `_ -> expr`, which matches any value
  and returns the original expression.

  ## Bad (compiles with error)

      with {:ok, val} <- x do
        val
      else
        :error
      end

  ## Good

      with {:ok, val} <- x do
        val
      else
        _ -> :error
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg ~s(expected -> clauses for :else in "with")

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_with_else_bare_value,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {:with, with_meta, args} ->
            new_args = fix_else_in_with(args)
            {:with, with_meta, new_args}

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

  defp fix_else_in_with(args) do
    Enum.map(args, fn
      blocks when is_list(blocks) ->
        Enum.map(blocks, fn
          {{:__block__, meta, [:else]}, body} = entry ->
            if bare_value?(body) do
              wrapped = [{:->, [], [[{:_, [], nil}], body]}]
              {{:__block__, meta, [:else]}, wrapped}
            else
              entry
            end

          other ->
            other
        end)

      other ->
        other
    end)
  end

  defp bare_value?(body) when is_list(body) do
    not match?([{:->, _, _} | _], body)
  end

  defp bare_value?(_), do: true

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
