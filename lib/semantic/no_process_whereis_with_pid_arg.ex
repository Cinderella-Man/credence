defmodule Credence.Semantic.NoProcessWhereisWithPidArg do
  @moduledoc """
  Fixes the unnecessary `case Process.whereis(...)` guard around
  `Process.demonitor/1`.

  LLMs frequently wrap `Process.demonitor(ref)` in a `case
  Process.whereis(self())` guard. `Process.whereis/1` expects an atom
  and crashes (`ArgumentError: not an atom`) when called with a pid.
  `Process.demonitor/1` is already safe on dead processes, so the guard
  is unnecessary.

  The compiler emits a generic compile-failure wrapper when the enclosing
  module cannot compile. `should_report?/2` confirms the source actually
  contains the anti-pattern before the rule fires.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "cannot compile module") and
      String.contains?(msg, "errors have been logged")
  end

  def match?(_), do: false

  @doc false
  def should_report?(_diagnostic, source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> has_whereis_pid_pattern?(ast)
      _ -> false
    end
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_process_whereis_with_pid_arg,
      message: "Process.whereis/1 called with a pid; guard is unnecessary around Process.demonitor/1",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:case, _meta, [subject, body_kw]} = node, acc
          when is_list(body_kw) ->
            if whereis_call?(subject) do
              case extract_do_clauses(body_kw) do
                {:ok, clauses} ->
                  case find_demonitor_clause(clauses) do
                    {:ok, replacement} -> {replacement, true}
                    :no_match -> {node, acc}
                  end

                :error ->
                  {node, acc}
              end
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  # Extract the clauses from the `do` block in a keyword list.
  # In Sourceror AST, `do: clauses` is `[{{:__block__, _, [:do]}, clauses}]`.
  defp extract_do_clauses(body_kw) do
    case Enum.find(body_kw, fn
           {{:__block__, _, [:do]}, _} -> true
           _ -> false
         end) do
      {{:__block__, _, [:do]}, clauses} -> {:ok, clauses}
      _ -> :error
    end
  end

  # Check if the AST contains `case Process.whereis(_) do ... end`.
  defp has_whereis_pid_pattern?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:case, _meta, [subject, _body]} = node, acc ->
          {node, acc || whereis_call?(subject)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Matches `Process.whereis(_)` in AST form:
  #   {{:., _, [{:__aliases__, _, [:Process]}, :whereis]}, _, [_]}
  defp whereis_call?(
         {{:., _, [{:__aliases__, _, [:Process]}, :whereis]}, _, args}
       )
       when is_list(args) and length(args) > 0,
       do: true

  defp whereis_call?(_), do: false

  # Given a case's `do` clauses, find the wildcard `_ -> body` clause
  # and return its body AST. This is the clause that contains
  # `Process.demonitor(ref)`.
  defp find_demonitor_clause(clauses) when is_list(clauses) do
    Enum.find_value(clauses, :no_match, fn
      {:->, _, [[{:_ , _, _}], body]} ->
        {:ok, body}

      _ ->
        nil
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
