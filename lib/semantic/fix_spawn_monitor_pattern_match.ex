defmodule Credence.Semantic.FixSpawnMonitorPatternMatch do
  @moduledoc """
  Fixes the pattern-match error caused by LLMs writing:

      {:ok, pid} = spawn_monitor(fn -> ... end)

  `spawn_monitor/1` and `spawn_monitor/3` return `{pid(), reference()}`, not
  `{:ok, pid()}`. The compiler emits:

      "the following pattern will never match:"

  when it detects the `{:ok, pid}` pattern on a `spawn_monitor` result.
  The fix keeps the pid binding in the pid position and discards the monitor
  reference:

      {:ok, pid} = spawn_monitor(...)  →  {pid, _} = spawn_monitor(...)

  ## Bad

      defmodule SpawnMonitorPatternFSMPM do
        def run do
          {:ok, pid} = spawn_monitor(fn -> :ok end)
          {pid, :done}
        end
      end

  ## Good

      defmodule SpawnMonitorPatternFSMPM do
        def run do
          {pid, _} = spawn_monitor(fn -> :ok end)
          {pid, :done}
        end
      end
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  # The diagnostic embeds the offending pattern; require the exact shape the
  # fix rewrites — `{:ok, var} = spawn_monitor(` as an unqualified call — so
  # other never-match diagnostics are left for other rules.
  @match_re ~r/the following pattern will never match:.*\{:ok, [a-z_][a-zA-Z0-9_?!]*\}\s*=\s*spawn_monitor\(/s

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    Regex.match?(@match_re, msg)
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
  def fix(source, diagnostic) do
    with diagnostic_line when is_integer(diagnostic_line) <- line(diagnostic),
         {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          {:=, assign_meta,
           [
             {:__block__, block_meta,
              [{{:__block__, ok_meta, [:ok]}, {var_name, var_meta, nil}}]},
             {:spawn_monitor, call_meta, call_args}
           ]} = node,
          acc
          when is_atom(var_name) and is_list(call_args) ->
            if Keyword.get(assign_meta, :line) == diagnostic_line do
              # {:ok, pid} = spawn_monitor(...)  →  {pid, _} = spawn_monitor(...)
              new_lhs =
                {:__block__, block_meta, [{{var_name, var_meta, nil}, {:_, ok_meta, nil}}]}

              {{:=, assign_meta, [new_lhs, {:spawn_monitor, call_meta, call_args}]}, true}
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

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_diagnostic), do: nil
end
