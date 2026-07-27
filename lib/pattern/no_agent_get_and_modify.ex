defmodule Credence.Pattern.NoAgentGetAndModify do
  @moduledoc """
  Fixes calls to `Agent.get_and_modify/2`, which does not exist in Elixir.

  LLMs frequently hallucinate `Agent.get_and_modify/2` — the correct function
  is `Agent.get_and_update/2`, which has identical semantics (receives state,
  returns `{reply, new_state}`).

  ## Bad

      Agent.get_and_modify(__MODULE__, fn state ->
        new_state = %{state | count: state.count + 1}
        {state.count, new_state}
      end)

  ## Good

      Agent.get_and_update(__MODULE__, fn state ->
        new_state = %{state | count: state.count + 1}
        {state.count, new_state}
      end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [{:__aliases__, _, [:Agent]}, :get_and_modify]}, _, _args} = node, acc ->
          {node, [build_issue(meta) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {{:., meta, [{:__aliases__, ameta, [:Agent]}, :get_and_modify]}, cmeta, args} ->
        {{:., meta, [{:__aliases__, ameta, [:Agent]}, :get_and_update]}, cmeta, args}

      node ->
        node
    end)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_agent_get_and_modify,
      message:
        "`Agent.get_and_modify/2` does not exist in Elixir. " <>
          "Replace with `Agent.get_and_update/2`.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
