defmodule Credence.Semantic.FixTaskAsyncStreamCaseMatch do
  @moduledoc """
  Repairs the LLM anti-pattern of wrapping `Task.async_stream/3` in a `case`
  expression expecting `{:ok, results}` / `{:error, reason}` tuples.

  `Task.async_stream/3` returns a lazy `Stream` (a function), never a tagged
  tuple, so every tuple clause is dead and the `case` raises `CaseClauseError`
  on any execution. The compiler emits one warning per dead clause:

      the following clause will never match:

          {:ok, results} ->

      because it attempts to match on the result of:

          Task.async_stream(elements, fun, max_concurrency: 4)

      which has type:

          dynamic(({:cont or :halt or :suspend, term()}, term() -> term()))

  The fix removes dead tuple clauses beside live clauses. When every clause is
  dead, it replaces the `case` with an explicit `CaseClauseError` after
  evaluating the stream once, preserving the original runtime behaviour.

  Safety: the rewrite is applied only when **every** clause of the `case` is a
  plain tagged 2-tuple pattern (no guard, no catch-all, no other shapes). The
  diagnostic proves the subject has a function type, so such a `case` can never
  take any branch — the original code crashes on every execution that reaches
  it, and replacing it with the intended ok-path cannot change the answer of
  any run that used to succeed. A `case` with a live clause (e.g. a trailing
  `stream ->` catch-all) also triggers this warning for its dead tuple clause,
  but rewriting it would delete the real runtime path — those are left alone.

  ## Bad

      defmodule ExampleFTASCM do
        def run(elements, fun) do
          total =
            case Task.async_stream(elements, fun) do
              {:ok, results} -> Enum.count(results)
              {:error, _reason} -> 0
            end

          total + 1
        end
      end

  ## Good

      defmodule ExampleFTASCM do
        def run(elements, fun) do
          total =
            case Task.async_stream(elements, fun) do
              unmatched_stream ->
                raise CaseClauseError, term: unmatched_stream
            end

          total + 1
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # The diagnostic embeds the dead clause, the subject, and the subject's
  # type. Require all three shapes the fix depends on: a tagged-tuple clause,
  # `Task.async_stream(` as the direct subject (whitespace-anchored, so
  # `MyTask.async_stream(` cannot match), and a function type (`->`) — so a
  # tuple-returning shadow of `Task` can never reach the fix.
  @match_re ~r/the following clause will never match:\s+\{:[a-z_]\w*,.*because it attempts to match on the result of:\s+Task\.async_stream\(.*which has type:.*->/s

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    Regex.match?(@match_re, msg)
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
  def fix(source, diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source),
         target_line when is_integer(target_line) <- line(diagnostic),
         {:ok, target_tag} <- diagnostic_tag(diagnostic) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:case, _case_meta, [subject, clauses_kw]} = node, false ->
            with true <- async_stream_call?(subject),
                 {:ok, clauses} <- clause_list(clauses_kw),
                 {:ok, target} <- clause_at_line(clauses, target_line),
                 true <- dead_tuple_clause?(target),
                 true <- clause_tag(target) |> Atom.to_string() == target_tag do
              if Enum.all?(clauses, &dead_tuple_clause?/1) do
                {raise_case_clause(subject), true}
              else
                remaining = List.delete(clauses, target)
                {{:case, elem(node, 1), [subject, put_clauses(clauses_kw, remaining)]}, true}
              end
            else
              _ -> {node, false}
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

  defp clause_list([{{:__block__, _do_meta, [:do]}, clauses}]) when is_list(clauses),
    do: {:ok, clauses}

  defp clause_list(_), do: :error

  # A clause whose pattern is a plain tagged 2-tuple — `{:tag, subpattern}`
  # with no guard. Against a function-typed subject such a clause can never
  # match, so a case built only from these always raises CaseClauseError.
  defp dead_tuple_clause?({:->, _arrow_meta, [[pattern], _body]}), do: tagged_pair?(pattern)
  defp dead_tuple_clause?(_), do: false

  defp tagged_pair?({:__block__, _, [{{:__block__, _, [tag]}, _sub}]}) when is_atom(tag), do: true
  defp tagged_pair?(_), do: false

  defp clause_tag({:->, _, [[{:__block__, _, [{{:__block__, _, [tag]}, _sub}]}], _body]}),
    do: tag

  defp clause_tag(_), do: nil

  defp diagnostic_tag(%{message: message}) do
    case Regex.run(~r/the following clause will never match:\s+\{:([a-z_]\w*),/s, message) do
      [_, tag] -> {:ok, tag}
      _ -> :error
    end
  end

  defp diagnostic_tag(_), do: :error

  defp clause_at_line(clauses, target_line) do
    case Enum.find(clauses, fn
           {:->, meta, _} -> meta[:line] == target_line
           _ -> false
         end) do
      nil -> :error
      clause -> {:ok, clause}
    end
  end

  defp put_clauses([{{:__block__, do_meta, [:do]}, _clauses}], clauses),
    do: [{{:__block__, do_meta, [:do]}, clauses}]

  defp raise_case_clause(subject) do
    quote generated: true do
      case unquote(subject) do
        unmatched_stream -> raise CaseClauseError, term: unmatched_stream
      end
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil
end
