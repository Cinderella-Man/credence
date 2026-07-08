defmodule Credence.Semantic.NoProcessSendAfterWithVariableInfinity do
  @moduledoc """
  Fixes calls to `Process.send_after/3` where the timeout is a variable
  (not a literal) that could hold `:infinity` at runtime.

  Unlike `NoProcessSendAfterInfinity` which catches literal `:infinity` args,
  this rule catches variables that may hold `:infinity` at runtime (common in
  GenServer cleanup patterns where the interval comes from configurable options).

  The fix wraps the `Process.send_after/3` call in a private helper function
  that pattern-matches on `:infinity` (returns `:ok`) vs integer timeout
  (delegates to `Process.send_after/3`).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "invalid args for &"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_process_send_after_with_variable_infinity,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        calls = collect_variable_send_after_calls(ast)

        case calls do
          [] ->
            source

          _ ->
            source
            |> apply_call_patches(calls)
            |> add_helper_functions(ast, calls)
        end

      _ ->
        source
    end
  end

  # Walk the AST and collect Process.send_after/3 calls where the third arg
  # is a variable (not a literal atom or integer).
  defp collect_variable_send_after_calls(ast) do
    {_, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Process]}, :send_after]}, _, args} = node, acc
        when is_list(args) and length(args) == 3 ->
          [_, msg_arg, timeout_arg] = args

          case timeout_arg do
            {:__block__, _, [value]} when is_atom(value) or is_integer(value) ->
              # Literal atom or integer — not a variable, skip
              {node, acc}

            _ ->
              msg = extract_atom(msg_arg)
              range = Sourceror.get_range(node)
              {node, [{range, msg, timeout_arg} | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(calls)
  end

  defp extract_atom({:__block__, _, [atom]}) when is_atom(atom), do: atom
  defp extract_atom(_), do: :msg

  # Replace each Process.send_after(self(), :msg, var) call with schedule_msg(var).
  defp apply_call_patches(source, calls) do
    Enum.reduce(calls, source, fn {range, msg, timeout_arg}, acc ->
      helper_name = :"schedule_#{msg}"
      timeout_str = Sourceror.to_string(timeout_arg)
      replacement = "#{helper_name}(#{timeout_str})"
      Sourceror.patch_string(acc, [%{range: range, change: replacement}])
    end)
  end

  # Insert private helper function definitions before the module's closing end.
  defp add_helper_functions(source, ast, calls) do
    unique_msgs =
      calls
      |> Enum.map(fn {_, msg, _} -> msg end)
      |> Enum.uniq()
      |> Enum.sort()

    module_end_line = find_module_end_line(ast)

    helpers_text =
      Enum.map_join(unique_msgs, "\n\n", fn msg ->
        generate_helper_text(msg)
      end)

    lines = String.split(source, "\n")
    {before, [end_line | rest]} = Enum.split(lines, module_end_line - 1)
    Enum.join(before ++ ["", helpers_text, end_line] ++ rest, "\n")
  end

  defp generate_helper_text(msg) do
    "  defp schedule_#{msg}(:infinity), do: :ok\n" <>
      "  defp schedule_#{msg}(interval) when is_integer(interval) do\n" <>
      "    Process.send_after(self(), :#{msg}, interval)\n" <>
      "  end"
  end

  defp find_module_end_line(ast) do
    {_, end_line} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, meta, _} = node, _ ->
          case meta[:end][:line] do
            nil -> {node, nil}
            line -> {node, line}
          end

        node, acc ->
          {node, acc}
      end)

    end_line || 999
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
