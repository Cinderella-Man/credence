defmodule Credence.Semantic.NoSendSelfInTask do
  @moduledoc """
  Fixes `send(self(), ...)` called inside a `Task.start_link/1` or
  `Task.async/1` callback.

  LLMs frequently spawn a `Task` and call `send(self(), msg)` inside the
  callback, intending to message the parent process. Inside the spawned task,
  `self()` returns the *task* PID, not the GenServer PID, so the message
  vanishes and tests timeout. Under `--warnings-as-errors` this can surface as
  a compile-time diagnostic from project-specific analysis tools.

  The fix captures `parent = self()` before the `Task.start_link` call and
  replaces `self()` with `parent` inside the anonymous function.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "send(self(), ...) called inside a Task callback"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_send_self_in_task,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        case find_task_self_range(ast) do
          {:ok, task_range, self_ranges} ->
            apply_fix(source, task_range, self_ranges)

          :error ->
            source
        end

      _ ->
        source
    end
  end

  @self_len byte_size("self()")

  defp find_task_self_range(ast) do
    {_ast, _acc} =
      Macro.prewalk(ast, nil, fn
        node, nil ->
          case node do
            {{:., _, [{:__aliases__, _, [:Task]}, fun]}, _, [fn_node]}
            when fun in [:start_link, :async] ->
              case find_self_in_fn(fn_node) do
                {:ok, self_ranges} ->
                  case Sourceror.get_range(node) do
                    %Sourceror.Range{} = task_range ->
                      throw({:found, task_range, self_ranges})

                    _ ->
                      {node, nil}
                  end

                :error ->
                  {node, nil}
              end

            _ ->
              {node, nil}
          end

        node, acc ->
          {node, acc}
      end)

    :error
  catch
    {:found, task_range, self_ranges} -> {:ok, task_range, self_ranges}
  end

  defp find_self_in_fn({:fn, _, [{:->, _, [[], body]}]}) do
    ranges = collect_self_ranges(body)
    if ranges == [], do: :error, else: {:ok, ranges}
  end

  defp find_self_in_fn(_), do: :error

  defp collect_self_ranges(ast) do
    {_ast, ranges} =
      Macro.prewalk(ast, [], fn
        {:self, _meta, []} = node, acc ->
          case Sourceror.get_range(node) do
            %Sourceror.Range{} = range -> {node, [range | acc]}
            _ -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(ranges)
  end

  defp apply_fix(source, task_range, self_ranges) do
    # Step 1: Replace self() with parent inside the fn
    # Process in reverse order to preserve line/col positions
    source =
      Enum.reduce(Enum.reverse(self_ranges), source, fn range, src ->
        line = range.start[:line]
        col = range.start[:column]
        lines = String.split(src, "\n")
        line_text = Enum.at(lines, line - 1)

        col0 = col - 1
        before = binary_part(line_text, 0, col0)

        after_ =
          binary_part(line_text, col0 + @self_len, byte_size(line_text) - col0 - @self_len)

        new_line = before <> "parent" <> after_

        List.replace_at(lines, line - 1, new_line) |> Enum.join("\n")
      end)

    # Step 2: Insert "parent = self()" before the Task line
    task_line = task_range.start[:line]
    indent = get_indent(source, task_line)
    assign_line = "#{indent}parent = self()"

    lines = String.split(source, "\n")
    {before, after_} = Enum.split(lines, task_line - 1)
    Enum.join(before ++ [assign_line, ""] ++ after_, "\n")
  end

  defp get_indent(source, line_no) do
    lines = String.split(source, "\n")
    line = Enum.at(lines, line_no - 1, "")
    Regex.run(~r/^\s*/, line) |> hd()
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
