defmodule Credence.Pattern.FixTaskShutdownBrutalKill do
  @moduledoc """
  Detects `Task.shutdown(task, :brutal)` and fixes it to
  `Task.shutdown(task, :brutal_kill)`.

  LLMs frequently write `:brutal` instead of the correct `:brutal_kill` atom,
  causing a `FunctionClauseError` on every invocation. This deterministic atom
  fix is always safe and no existing rule covers it.

  ## Bad

      Task.shutdown(task, :brutal)

  ## Good

      Task.shutdown(task, :brutal_kill)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Task]}, :shutdown]}, meta,
         [_task, {:__block__, _, [:brutal]}]} = node,
        acc ->
          issue = %Issue{
            rule: :fix_task_shutdown_brutal_kill,
            message:
              "Task.shutdown/2 does not accept :brutal — use :brutal_kill instead.",
            meta: %{line: Keyword.get(meta, :line)}
          }

          {node, [issue | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      {{:., dot_meta, [{:__aliases__, alias_meta, [:Task]}, :shutdown]}, call_meta,
       [task_arg, {:__block__, block_meta, [:brutal]}]} ->
        {{:., dot_meta, [{:__aliases__, alias_meta, [:Task]}, :shutdown]}, call_meta,
         [task_arg, {:__block__, block_meta, [:brutal_kill]}]}

      node ->
        node
    end)
  end
end
