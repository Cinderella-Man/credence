defmodule Credence.Semantic.FixTaskRefFieldAccess do
  @moduledoc """
  Fixes the compiler diagnostic caused by LLM-hallucinated `Task.ref(task)` calls.

  LLMs frequently hallucinate `Task.ref(task)` to obtain a task reference, but
  `Task.ref/1` does not exist in the Elixir standard library. The correct idiom
  is struct field access: `task.ref`.

  The compiler emits a "is currently being defined" diagnostic when the
  hallucinated call collides with a module definition. The fix rewrites the
  remote function call `Task.ref(arg)` into the field access `arg.ref`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring "is currently being defined"

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_task_ref_field_access,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    with {:ok, ast} <- Sourceror.parse_string(source) do
      {new_ast, changed} =
        Macro.prewalk(ast, false, fn
          # Match: Task.ref(arg) — remote call on Task module with single arg
          {{:., dot_meta, [{:__aliases__, _alias_meta, [:Task]}, :ref]}, call_meta, [arg]},
          _acc ->
            # Rewrite to: arg.ref — field access on the argument
            new_meta =
              call_meta
              |> Keyword.delete(:closing)
              |> Keyword.put(:no_parens, true)

            {{{:., dot_meta, [arg, :ref]}, new_meta, []}, true}

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
