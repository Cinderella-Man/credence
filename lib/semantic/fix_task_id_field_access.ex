defmodule Credence.Semantic.FixTaskIdFieldAccess do
  @moduledoc """
  Fixes the type-checker warning caused by accessing `.id` on a `%Task{}`.

  LLMs frequently hallucinate `task.id` on `%Task{}` structs — the struct has
  no `:id` field; its unique identifier is the monitor reference in `:ref`.
  The compiler emits:

      unknown key .id in expression:

          task.id

      the given type does not have the given key:

          dynamic(%Task{mfa: {atom(), atom(), integer()}, owner: pid(), pid: pid(), ref: term()})

  The fix replaces exactly the flagged `.id` access with `.ref`, located via
  the diagnostic's line/column (the column points at the `id` token, and the
  compiler counts columns in graphemes).

  The rule is deliberately narrow:

    * the same "unknown key .id" warning on any other type does not match —
      the flagged type (the one printed under "does not have the given key:")
      must be the `Task` struct itself, not merely a type that mentions
      `%Task{}` somewhere inside (rewriting `.id` to `.ref` on a non-Task
      would fix nothing);
    * the fix edits only the flagged position, and only after verifying the
      source there really is a `.id` field access that is not part of a longer
      identifier (`.identity`, `.id?`, …); on any mismatch — including a
      diagnostic without a column — it is a no-op rather than a guess.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "unknown key .id in expression:") and flagged_type_is_task?(msg)
  end

  def match?(_), do: false

  defp flagged_type_is_task?(msg) do
    case String.split(msg, "the given type does not have the given key:", parts: 2) do
      [_, rest] ->
        type = String.trim_leading(rest)
        String.starts_with?(type, "dynamic(%Task{") or String.starts_with?(type, "%Task{")

      _ ->
        false
    end
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_task_id_field_access,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{position: {line_no, col}}) when is_integer(line_no) and is_integer(col) do
    lines = String.split(source, "\n")

    with target when is_binary(target) <- Enum.at(lines, line_no - 1),
         {:ok, fixed} <- replace_id_at(target, col) do
      lines |> List.replace_at(line_no - 1, fixed) |> Enum.join("\n")
    else
      _ -> source
    end
  end

  def fix(source, _diagnostic), do: source

  # `col` (1-based, graphemes) points at the `i` of the flagged `id`, so the
  # `.` sits at grapheme `col - 1`. Verify that shape before editing.
  defp replace_id_at(line, col) when is_integer(col) and col >= 2 do
    {prefix, rest} = String.split_at(line, col - 2)

    case rest do
      ".id" <> tail ->
        if extends_identifier?(tail), do: :error, else: {:ok, prefix <> ".ref" <> tail}

      _ ->
        :error
    end
  end

  defp replace_id_at(_line, _col), do: :error

  # A char that would make the flagged token longer than `id`. Non-ASCII is
  # treated as extending (Elixir allows Unicode identifiers) — safer to skip.
  defp extends_identifier?(<<c, _::binary>>)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c in [?_, ??, ?!],
       do: true

  defp extends_identifier?(<<c::utf8, _::binary>>) when c > 127, do: true
  defp extends_identifier?(_), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
