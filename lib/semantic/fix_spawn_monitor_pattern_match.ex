defmodule Credence.Semantic.FixSpawnMonitorPatternMatch do
  @moduledoc """
  Fixes the pattern-match error caused by LLMs writing:

      {:ok, pid} = spawn_monitor(fn -> ... end)

  `spawn_monitor/1` returns `{reference(), pid()}`, not `{:ok, pid()}`.
  The compiler emits:

      "the following pattern will never match:"

  when it detects the `{:ok, pid}` pattern on a `spawn_monitor/1` result.
  The fix replaces `:ok` with `_ref` in the tuple destructure:

      {:ok, pid} = spawn_monitor(...)  →  {_ref, pid} = spawn_monitor(...)
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "the following pattern will never match:"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_spawn_monitor_pattern_match,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:=, assign_meta,
           [
             {:__block__, block_meta,
              [{{:__block__, ok_meta, [:ok]}, {var_name, var_meta, nil}}]},
             {:spawn_monitor, call_meta, call_args}
           ]} = _node,
          _acc
          when is_atom(var_name) ->
            # {:ok, pid} = spawn_monitor(...)  →  {_ref, pid} = spawn_monitor(...)
            new_lhs = {:__block__, block_meta, [{{:_ref, ok_meta, nil}, {var_name, var_meta, nil}}]}
            {{:=, assign_meta, [new_lhs, {:spawn_monitor, call_meta, call_args}]}, true}

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
