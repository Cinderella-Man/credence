defmodule Credence.Semantic.NoHallucinatedAgentUpdateAnd do
  @moduledoc """
  Fixes the compile warning caused by `Agent.update_and/2` — a function that
  does not exist in the Agent module.

  LLMs frequently hallucinate `Agent.update_and/2` when they mean
  `Agent.get_and_update/2` (both take an agent name and a function that
  returns a 2-tuple). The compiler emits:

      "Agent.update_and/2 is undefined or private. Did you mean:
          * update/2
          * update/3
          …"

  The fix rewrites `Agent.update_and(agent, fun)` to
  `Agent.get_and_update(agent, fun)` — the correct function name with the
  same signature and semantics (returns the value from the 2-tuple).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "Agent.update_and/"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_hallucinated_agent_update_and,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {{:., dot_meta, [{:__aliases__, alias_meta, [:Agent]}, :update_and]}, call_meta, args},
          _acc ->
            {{{:., dot_meta, [{:__aliases__, alias_meta, [:Agent]}, :get_and_update]}, call_meta,
              args}, true}

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
