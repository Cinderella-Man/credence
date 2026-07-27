defmodule Credence.Semantic.FixTaskIdFieldAccess do
  @moduledoc """
  Fixes the compiler warning caused by accessing `.id` on a `Task` struct.

  LLMs frequently hallucinate `task.id` on `%Task{}` structs — the correct
  field name is `.ref`. The compiler emits:

      "unknown key .id in expression:\n\n    task.id\n\nthe given type does not have the given key"

  The fix replaces `.id` with `.ref` on the flagged line.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "unknown key .id"

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_task_id_field_access,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    line_no = line(diagnostic)

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {l, ^line_no} -> String.replace(l, ".id", ".ref", global: false)
      {l, _} -> l
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
