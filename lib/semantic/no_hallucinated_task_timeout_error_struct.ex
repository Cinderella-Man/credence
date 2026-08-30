defmodule Credence.Semantic.NoHallucinatedTaskTimeoutErrorStruct do
  @moduledoc """
  Fixes compile errors caused by LLM-hallucinated `%Task.TimeoutError{}`.

  LLMs frequently hallucinate `%Task.TimeoutError{}` in `Task.async_stream`
  timeout patterns — there is no such struct in Elixir (`Task.async_stream`
  emits `{:exit, :timeout}`). The compiler emits:

      "Task.TimeoutError.__struct__/1 is undefined, cannot expand struct Task.TimeoutError"

  The fix rewrites the hallucinated struct pattern to the correct idiom:

      {:exit, {%Task.TimeoutError{}, _stacktrace}}  →  {:exit, :timeout}

  ## The pattern-position diagnostic

  Elixir describes an undefined struct differently depending on where it sits:

      # expression position
      Task.TimeoutError.__struct__/1 is undefined, cannot expand struct Task.TimeoutError
      # pattern position
      struct Task.TimeoutError is undefined (module Task.TimeoutError is not available…)

  The shape this rule repairs is a **pattern**, so it accepts only the second
  message. Accepting the expression-position message would claim an error whose
  source shape this rule cannot safely repair.

  ## Bad

      defmodule TaskTimeoutWitnessHeadNHTTES do
        def handle({:exit, {%Task.TimeoutError{}, _stacktrace}}), do: :timeout
        def handle({:ok, v}), do: v
      end

  ## Good

      defmodule TaskTimeoutWitnessHeadNHTTES do
        def handle({:exit, :timeout}), do: :timeout
        def handle({:ok, v}), do: v
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "struct Task.TimeoutError is undefined"

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
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      case find_target(ast, position(diagnostic)) do
        nil ->
          source

        node ->
          Sourceror.patch_string(source, [
            %{range: Sourceror.get_range(node), change: ":exit, :timeout"}
          ])
      end
    else
      _ -> source
    end
  end

  defp find_target(ast, position) do
    {_ast, targets} =
      Macro.prewalk(ast, [], fn
        {{:__block__, _, [:exit]},
         {:__block__, _,
          [
            {{:%, _, [{:__aliases__, _, [:Task, :TimeoutError]}, {:%{}, _, _}]}, {_, _, _}}
          ]}} = node,
        acc ->
          {node, if(at_position?(node, position), do: [node | acc], else: acc)}

        node, acc ->
          {node, acc}
      end)

    List.first(targets)
  end

  defp at_position?(node, {line, column}) do
    case Sourceror.get_range(node) do
      %{start: start_pos, end: end_pos} ->
        start = {start_pos[:line], start_pos[:column]}
        finish = {end_pos[:line], end_pos[:column]}
        start <= {line, column} and {line, column} <= finish

      _ ->
        false
    end
  end

  defp at_position?(node, line) when is_integer(line) do
    case Sourceror.get_range(node) do
      %{start: [{:line, ^line} | _]} -> true
      _ -> false
    end
  end

  defp position(%{position: {line, column}}), do: {line, column}
  defp position(%{position: line}) when is_integer(line), do: line

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
