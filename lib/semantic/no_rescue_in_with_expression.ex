defmodule Credence.Semantic.NoRescueInWithExpression do
  @moduledoc """
  Fixes the compiler error when `rescue` or `catch` clauses appear inside a
  `with` expression.

  The compiler emits:

      "unexpected option :rescue in \"with\""
      "unexpected option :catch in \"with\""

  LLMs frequently write `rescue`/`catch` inside `with` blocks (confusing them
  with `try`), which is a compile error. The fix removes the invalid `rescue`
  and `catch` clauses and consolidates error handling into the `else` clause:
  the catch clause's patterns become the else clause (replacing any existing
  one), providing a unified error-handling path.

  ## Bad (compiles with error)

      with {:ok, dt} <- DateTime.from_iso8601(ts) do
        {:ok, dt}
      rescue
        _ -> {:ok, DateTime.from_iso8601!(ts)}
      catch
        _ -> {:error, :invalid_timestamp}
      end

  ## Good

      with {:ok, dt} <- DateTime.from_iso8601(ts) do
        {:ok, dt}
      else
        _ -> {:error, :invalid_timestamp}
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_rescue ~S(unexpected option :rescue in "with")
  @match_catch ~S(unexpected option :catch in "with")

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_rescue) or String.contains?(msg, @match_catch)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_rescue_in_with_expression,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      result =
        Macro.prewalk(ast, fn
          {:with, meta, args} = node ->
            clauses = Enum.take_while(args, &(not is_list(&1)))
            opts = Enum.find(args, [], &is_list/1)

            has_bad =
              Enum.any?(opts, fn
                {{:__block__, _, [key]}, _} when key in [:rescue, :catch] -> true
                _ -> false
              end)

            if has_bad do
              fix_with_opts(meta, clauses, opts, node)
            else
              node
            end

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

  defp fix_with_opts(meta, clauses, opts, fallback) do
    # Prefer catch clauses for the else body; fall back to rescue clauses
    handler_clauses =
      Enum.find_value(opts, fn
        {{:__block__, _, [:catch]}, clauses} -> clauses
        _ -> nil
      end) ||
        Enum.find_value(opts, fn
          {{:__block__, _, [:rescue]}, clauses} -> clauses
          _ -> nil
        end)

    if handler_clauses == nil do
      # No rescue or catch clause — nothing to fix
      fallback
    else
      has_else =
        Enum.any?(opts, fn
          {{:__block__, _, [:else]}, _} -> true
          _ -> false
        end)

      new_opts =
        opts
        |> Enum.reject(fn
          {{:__block__, _, [key]}, _} when key in [:rescue, :catch] -> true
          _ -> false
        end)
        |> then(fn remaining ->
          if has_else do
            Enum.map(remaining, fn
              {{:__block__, m, [:else]}, _} -> {{:__block__, m, [:else]}, handler_clauses}
              other -> other
            end)
          else
            # Add an else clause using metadata from the last existing option
            last_meta =
              case List.last(remaining) do
                {{:__block__, m, _}, _} -> m
                _ -> []
              end

            remaining ++ [{{:__block__, last_meta, [:else]}, handler_clauses}]
          end
        end)

      {:with, meta, clauses ++ [new_opts]}
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
