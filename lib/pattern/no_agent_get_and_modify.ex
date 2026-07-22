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

  # The patch covers only the `get_and_modify` identifier (whose position is the
  # outer call node's meta), not the whole call — re-rendering the call would
  # drop comments inside its `fn` argument and mangle `&Agent.get_and_modify/2`
  # captures.
  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Agent]}, :get_and_modify]}, cmeta, _args} = node, acc ->
          {node, rename_patch(cmeta) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  defp rename_patch(cmeta) do
    line = Keyword.get(cmeta, :line)
    column = Keyword.get(cmeta, :column)

    if is_integer(line) and is_integer(column) do
      # `Agent."get_and_modify"(...)` puts the identifier's position at the
      # opening quote; the token is two bytes longer than the bare name.
      span =
        byte_size("get_and_modify") +
          if Keyword.has_key?(cmeta, :delimiter), do: 2, else: 0

      [
        %{
          range: %{
            start: [line: line, column: column],
            end: [line: line, column: column + span]
          },
          change: "get_and_update"
        }
      ]
    else
      []
    end
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
