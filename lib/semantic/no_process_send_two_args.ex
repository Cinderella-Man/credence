defmodule Credence.Semantic.NoProcessSendTwoArgs do
  @moduledoc """
  Fixes calls to `Process.send/2` which is undefined.

  `Process.send/3` requires a third `opts` argument; LLMs frequently write
  `Process.send(dest, msg)` (arity 2) which is undefined. The fix replaces
  `Process.send(pid, msg)` with the equivalent `send(pid, msg)` (Kernel.send/2).

  The compiler emits a type-checking diagnostic when this anti-pattern is present.
  `should_report?/2` confirms the source actually contains the two-arg call before
  the rule fires.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "expected a map or struct when accessing"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @doc false
  def should_report?(_diagnostic, source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> has_process_send_two_args?(ast)
      _ -> false
    end
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_process_send_two_args,
      message:
        "Process.send/2 is undefined; use Kernel.send/2 instead",
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
              {:__aliases__, _, [:Process]},
              :send
            ]}, meta, [arg1, arg2]},
          _acc ->
            {{:send, meta, [arg1, arg2]}, true}

          node, acc ->
            {node, acc}
        end)

      if changed, do: Sourceror.to_string(new_ast), else: source
    else
      _ -> source
    end
  end

  defp has_process_send_two_args?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {{:., _,
          [
            {:__aliases__, _, [:Process]},
            :send
          ]}, _, [_, _]},
        _acc ->
          {nil, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
