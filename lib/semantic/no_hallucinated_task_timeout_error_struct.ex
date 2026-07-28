defmodule Credence.Semantic.NoHallucinatedTaskTimeoutErrorStruct do
  @moduledoc """
  Fixes compile errors caused by LLM-hallucinated `%Task.TimeoutError{}`.

  LLMs frequently hallucinate `%Task.TimeoutError{}` in `Task.async_stream`
  timeout patterns — there is no such struct in Elixir (`Task.async_stream`
  emits `{:exit, :timeout}`). The compiler emits:

      "Task.TimeoutError.__struct__/1 is undefined, cannot expand struct Task.TimeoutError"

  The fix rewrites the hallucinated struct pattern to the correct idiom:

      {:exit, {%Task.TimeoutError{}, _stacktrace}}  →  {:exit, :timeout}
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "Task.TimeoutError.__struct__/1 is undefined"

  @impl true
  def priority, do: 100

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_task_timeout_error_struct,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # Match {:exit, {%Task.TimeoutError{}, _stacktrace}} pattern
          {{:__block__, exit_meta, [:exit]},
           {:__block__, val_meta,
            [
              {{:%, _,
                [
                  {:__aliases__, _, [:Task, :TimeoutError]},
                  {:%{}, _, _}
                ]}, {_, _, _}}
            ]}},
          _acc ->
            {{{:__block__, exit_meta, [:exit]}, {:__block__, val_meta, [:timeout]}}, true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
