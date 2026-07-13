defmodule Credence.Semantic.FixTaskAsyncStreamCaseMatch do
  @moduledoc """
  Repairs the LLM anti-pattern of wrapping `Task.async_stream/3` in a `case`
  expression expecting `{:ok, results}` / `{:error, reason}` tuples.

  `Task.async_stream/3` returns a `Stream`, not a tagged tuple. The `case`
  wrapper produces unreachable-clause warnings and raises `CaseClauseError`
  at runtime. The compiler emits:

      the following clause will never match:

          {:ok, results}

      because it attempts to match on the result of:

          Task.async_stream(elements, fun, max_concurrency: 4)

  The fix removes the `case` wrapper, binds the stream to the variable from
  the `{:ok, var}` pattern, and drops both tuple-matching clauses.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_prefix "the following clause will never match:"
  @match_suffix "because it attempts to match on the result of:"
  @match_task "Task.async_stream"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_prefix) and
      String.contains?(msg, @match_suffix) and
      String.contains?(msg, @match_task)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_task_async_stream_case_match,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:case, _case_meta, [subject, clauses_kw]} = node, false ->
            if async_stream_call?(subject) do
              case extract_ok_body(clauses_kw) do
                {:ok, var_ref, body} ->
                  replacement = {:__block__, [], [{:=, [], [var_ref, subject]}, body]}
                  {replacement, true}

                :error ->
                  {node, false}
              end
            else
              {node, false}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Match Task.async_stream(...) remote call
  defp async_stream_call?({{:., _, [{:__aliases__, _, [:Task]}, :async_stream]}, _, _}), do: true
  defp async_stream_call?(_), do: false

  # Extract the {:ok, var} clause's variable reference and body from the case clauses.
  defp extract_ok_body([{{:__block__, _do_meta, [:do]}, clauses}]) when is_list(clauses) do
    Enum.find_value(clauses, :error, fn
      {:->, _arrow_meta, [[{:__block__, _, [{{:__block__, _, [:ok]}, {var, var_meta, nil}}]}], body]} ->
        {:ok, {var, var_meta, nil}, body}

      _ ->
        nil
    end)
  end

  defp extract_ok_body(_), do: :error

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
