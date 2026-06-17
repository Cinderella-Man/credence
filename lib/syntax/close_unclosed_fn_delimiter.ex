defmodule Credence.Syntax.CloseUnclosedFnDelimiter do
  @moduledoc """
  Repairs an `fn` closed with `)` **and** a leftover stray `end` on the next line.

  This is the sibling of `Credence.Syntax.NoUnclosedFnDelimiter`. That rule
  handles a plain `fn args -> body)` (an `fn` whose `end` is missing entirely).
  Here the LLM instead writes an inner block's `end`, then `)`, then leaves the
  `fn`'s would-be `end` dangling on the following line:

      Enum.map(row, fn element ->
        if element == 0 do min_value else element end)
      end

  The `end` closes the `if`, the `)` closes the `Enum.map` call, the `fn` body is
  never closed, and the next line's `end` no longer has a block to close. The
  repair inserts the missing `end` before the `)` and deletes the now-stray
  `end` line:

      Enum.map(row, fn element ->
        if element == 0 do min_value else element end end)

  Detection is driven by the parser itself — `Code.string_to_quoted/2` reports
  the exact `fn`/`)` mismatch, and the repair is committed only when removing a
  stray `end` makes the whole source parse. So the rule never matches `fn`/`do`/
  `end` words inside strings, heredocs, or comments, and a file unparseable for
  an unrelated reason is left untouched.

  This rule deliberately owns only the **stray-`end`** variant: when inserting
  `end` before `)` already yields parseable code (no stray `end`), that is
  `NoUnclosedFnDelimiter`'s case and this rule stays silent, so the two never
  both fire on the same input.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case repair(source) do
      {:fixed, _fixed, line} ->
        [
          %Issue{
            rule: :close_unclosed_fn_delimiter,
            message:
              "Unclosed `fn` delimiter — the `fn` body is not closed before `)`, " <>
                "and a stray `end` follows.",
            meta: %{line: line}
          }
        ]

      :no_fix ->
        []
    end
  end

  @impl true
  def fix(source) do
    case repair(source) do
      {:fixed, fixed, _line} -> fixed
      :no_fix -> source
    end
  end

  # Insert the missing `end` before the parser-pinpointed `)`, then delete the
  # stray `end` whose removal makes the whole source parse. Commit only when the
  # result parses. analyze and fix share this helper so they always agree.
  defp repair(source) do
    case detect(source) do
      {:ok, end_line, end_col} ->
        step1 = insert_end_before(source, end_line, end_col)

        cond do
          # Nothing spliced (the reported column was not a `)`): give up.
          step1 == source ->
            :no_fix

          # Inserting `end` left exactly the "extra `end` where the call's `)`
          # should close" error — i.e. there is a stray `end` to remove. (When
          # inserting `end` already parses, that is NoUnclosedFnDelimiter's case
          # and this branch is not taken, so the two rules never both fire.)
          stray_end_error?(step1) ->
            case remove_stray_end(step1, end_line - 1) do
              {:ok, step2} -> {:fixed, step2, end_line}
              :none -> :no_fix
            end

          true ->
            :no_fix
        end

      :none ->
        :no_fix
    end
  end

  defp parses?(source), do: match?({:ok, _}, Code.string_to_quoted(source))

  # Ask the parser whether an `fn` was closed by `)` instead of `end`, and where.
  defp detect(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == :fn and
             Keyword.get(meta, :expected_delimiter) == :end and
             Keyword.get(meta, :closing_delimiter) == :")" do
          {:ok, Keyword.get(meta, :end_line), Keyword.get(meta, :end_column)}
        else
          :none
        end

      _ ->
        :none
    end
  end

  # After inserting `end`, the leftover error is an extra `end` standing where
  # the enclosing call's `)` was expected.
  defp stray_end_error?(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        Keyword.get(meta, :error_type) == :mismatched_delimiter and
          Keyword.get(meta, :opening_delimiter) == :"(" and
          Keyword.get(meta, :closing_delimiter) == :end and
          Keyword.get(meta, :expected_delimiter) == :")"

      _ ->
        false
    end
  end

  defp insert_end_before(source, line_no, col)
       when is_integer(line_no) and is_integer(col) do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        source

      line ->
        case String.split_at(line, col - 1) do
          {before, ")" <> _ = rest} ->
            lines
            |> List.replace_at(line_no - 1, before <> " end" <> rest)
            |> Enum.join("\n")

          _ ->
            source
        end
    end
  end

  defp insert_end_before(source, _line, _col), do: source

  # Scanning from the insertion line downward (never back into a docstring
  # above), delete the first bare `end` line whose removal makes the whole
  # source parse. The downward scan + parse check pick the structurally-adjacent
  # stray `end`, never a bare `end` that is string/heredoc content.
  defp remove_stray_end(source, start_idx) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, idx} -> idx >= start_idx and bare_end?(line) end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.find_value(:none, fn idx ->
      candidate = lines |> List.delete_at(idx) |> Enum.join("\n")
      if parses?(candidate), do: {:ok, candidate}, else: false
    end)
  end

  defp bare_end?(line), do: Regex.match?(~r/^\s*end\s*$/, line)
end
