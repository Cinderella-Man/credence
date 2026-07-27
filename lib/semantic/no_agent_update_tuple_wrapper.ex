defmodule Credence.Semantic.NoAgentUpdateTupleWrapper do
  @moduledoc """
  Fixes `Agent.update` callbacks that wrap the new state in `{:ok, state}`.

  LLMs frequently return `{:ok, new_state}` from `Agent.update` callbacks
  (Python try/except→ok pattern). This causes a runtime `BadMapError` because
  Agent expects a bare state value, not a tuple.

  The fix unwraps the `{:ok, ...}` tuple so the callback returns the bare state.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "Agent.update callback should return new state, not {:ok, state}"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_agent_update_tuple_wrapper,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., _,
            [
              {:__aliases__, _, [:Agent]},
              :update
            ]}, meta_update, [arg1, {:fn, meta_fn, clauses}]},
          false ->
            new_clauses =
              Enum.map(clauses, fn
                {:->, meta_arrow, [params, body]} ->
                  case body do
                    {:__block__, b_meta, stmts} when is_list(stmts) ->
                      last = List.last(stmts)

                      case last do
                        # Multi-statement: last stmt is a __block__ wrapping {:ok, val}
                        {:__block__, _, [{{:__block__, _, [:ok]}, val}]} ->
                          new_stmts = List.replace_at(stmts, -1, val)
                          {:->, meta_arrow, [params, {:__block__, b_meta, new_stmts}]}

                        # Single-statement: the tuple itself is {:ok, val}
                        {{:__block__, _, [:ok]}, val} ->
                          new_stmts = List.replace_at(stmts, -1, val)
                          {:->, meta_arrow, [params, {:__block__, b_meta, new_stmts}]}

                        _ ->
                          {:->, meta_arrow, [params, body]}
                      end

                    _ ->
                      {:->, meta_arrow, [params, body]}
                  end
              end)

            {{{:., [], [{:__aliases__, [], [:Agent]}, :update]}, meta_update,
              [arg1, {:fn, meta_fn, new_clauses}]}, true}

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
