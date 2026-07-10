defmodule Credence.Semantic.NoProcessSendAfterLiteralInfinity do
  @moduledoc """
  Fixes calls to `Process.send_after/3` where the timeout is a variable
  that could hold `:infinity` at runtime.

  LLMs commonly pass `:infinity` (often from a configurable interval option)
  to disable periodic timers, which crashes at runtime since `:erlang.send_after/3`
  requires an integer. The fix wraps the call in
  `if variable != :infinity do ... end` to prevent the ArgumentError.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "in code block has no effect as it is never returned"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_process_send_after_literal_infinity,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      patches = collect_patches(ast)

      case patches do
        [] ->
          source

        _ ->
          Enum.reduce(patches, source, fn patch, acc ->
            Sourceror.patch_string(acc, [patch])
          end)
      end
    else
      _ -> source
    end
  end

  # Walk the AST and collect patches for Process.send_after/3 calls
  # where the third argument is a variable (not a literal).
  defp collect_patches(ast) do
    {_, patches} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Process]}, :send_after]}, _,
         [_, _, {var_name, _, nil}]} = node,
        acc
        when is_atom(var_name) ->
          case Sourceror.get_range(node) do
            %Sourceror.Range{} = range ->
              call_str = Sourceror.to_string(node)
              change = "if #{var_name} != :infinity do\n  #{call_str}\nend"
              {node, [%{range: range, change: change} | acc]}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
