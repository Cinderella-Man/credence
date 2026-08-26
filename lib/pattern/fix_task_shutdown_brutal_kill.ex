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
    task_shadowed? = task_alias_shadowed?(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, acc ->
          if repair(node, task_shadowed?) == node do
            {node, acc}
          else
            issue = %Issue{
              rule: :fix_task_shutdown_brutal_kill,
              message: "Task.shutdown/2 does not accept :brutal — use :brutal_kill instead.",
              meta: %{line: Keyword.get(node_meta(node), :line)}
            }

            {node, [issue | acc]}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    task_shadowed? = task_alias_shadowed?(ast)
    RuleHelpers.patches_from_postwalk(ast, &repair(&1, task_shadowed?))
  end

  defp repair(
         {{:., dot_meta, [{:__aliases__, alias_meta, module}, :shutdown]}, call_meta,
          [task_arg, {:__block__, block_meta, [:brutal]}]} = node,
         task_shadowed?
       ) do
    if task_module?(module, task_shadowed?) do
      {{:., dot_meta, [{:__aliases__, alias_meta, module}, :shutdown]}, call_meta,
       [task_arg, {:__block__, block_meta, [:brutal_kill]}]}
    else
      node
    end
  end

  defp repair(
         {:|>, pipe_meta,
          [
            task_arg,
            {{:., dot_meta, [{:__aliases__, alias_meta, module}, :shutdown]}, call_meta,
             [{:__block__, block_meta, [:brutal]}]}
          ]} = node,
         task_shadowed?
       ) do
    if task_module?(module, task_shadowed?) do
      {:|>, pipe_meta,
       [
         task_arg,
         {{:., dot_meta, [{:__aliases__, alias_meta, module}, :shutdown]}, call_meta,
          [{:__block__, block_meta, [:brutal_kill]}]}
       ]}
    else
      node
    end
  end

  defp repair(node, _task_shadowed?), do: node

  defp task_module?([:Task], task_shadowed?), do: not task_shadowed?
  defp task_module?([Elixir, :Task], _task_shadowed?), do: true
  defp task_module?(_module, _task_shadowed?), do: false

  defp task_alias_shadowed?(ast) do
    {_ast, shadowed?} =
      Macro.prewalk(ast, false, fn
        {:alias, _, [{:__aliases__, _, target}, opts]} = node, shadowed?
        when is_list(target) and is_list(opts) ->
          {node, shadowed? or shadows_task?(target, alias_as(opts))}

        {:alias, _, [{:__aliases__, _, target}]} = node, shadowed? when is_list(target) ->
          {node, shadowed? or shadows_task?(target, nil)}

        node, shadowed? ->
          {node, shadowed?}
      end)

    shadowed?
  end

  defp alias_as(opts) do
    Enum.find_value(opts, fn
      {:as, value} -> value
      {{:__block__, _, [:as]}, value} -> value
      _other -> nil
    end)
  end

  defp shadows_task?(target, {:__aliases__, _, [:Task]}), do: target != [:Task]
  defp shadows_task?(target, nil), do: List.last(target) == :Task and target != [:Task]
  defp shadows_task?(_target, _as), do: false

  defp node_meta({_form, meta, _args}), do: meta
end
