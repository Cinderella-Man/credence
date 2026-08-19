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
  the exact `fn`/`)` mismatch, and a stray `end` line is deleted only when its
  removal demonstrably clears the leftover extra-`end` error. That check is what
  keeps the rule out of strings, heredocs and comments: deleting a line that is
  heredoc *content* removes no `end` token, so the extra-`end` error survives
  byte-for-byte and the candidate is rejected.

  The check is deliberately **local** — it does not ask whether the whole file
  parses afterwards. `Credence.Syntax` runs this round over source that is
  unparseable by definition and expects unparseable intermediate states (see its
  moduledoc), so a whole-file gate would make the rule decline on any file
  carrying a second fault — including a second copy of this very bug. Each
  occurrence is repaired on its own, and `analyze/1` reports every one the fix
  rewrites, at the line it occupies in the **input**.

  A fault the rule cannot see past is still declined: if the parser's *first*
  complaint about the file is something other than an `fn` closed by `)`, there
  is no repair to make and the source is returned untouched.

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
      {:fixed, _fixed, lines} ->
        Enum.map(lines, fn line ->
          %Issue{
            rule: :close_unclosed_fn_delimiter,
            message:
              "Unclosed `fn` delimiter — the `fn` body is not closed before `)`, " <>
                "and a stray `end` follows.",
            meta: %{line: line}
          }
        end)

      :no_fix ->
        []
    end
  end

  @impl true
  def fix(source) do
    case repair(source) do
      {:fixed, fixed, _lines} -> fixed
      :no_fix -> source
    end
  end

  # Repair every occurrence in the file, one pass each. analyze and fix share
  # this helper so they always agree on both the source and the reported lines.
  #
  # Each pass removes exactly one line, so `removed` — the input line numbers
  # already deleted, ascending — is all that is needed to translate a later
  # pass's line numbers back into the caller's own coordinates. Termination is
  # by construction: the line count strictly decreases every pass.
  defp repair(source), do: repair(source, [], [])

  defp repair(source, reported, removed) do
    case repair_once(source) do
      {:fixed, fixed, line, deleted_line} ->
        repair(
          fixed,
          [input_line(line, removed) | reported],
          Enum.sort([input_line(deleted_line, removed) | removed])
        )

      :no_fix when reported == [] ->
        :no_fix

      :no_fix ->
        {:fixed, source, Enum.reverse(reported)}
    end
  end

  # A line number in the current source, back in the input's numbering: every
  # already-deleted input line at or above it shifted it up by one.
  defp input_line(line, removed) do
    Enum.reduce(removed, line, fn deleted, acc ->
      if deleted <= acc, do: acc + 1, else: acc
    end)
  end

  # Insert the missing `end` before the parser-pinpointed `)`, then delete the
  # stray `end` whose removal clears the leftover extra-`end` error.
  defp repair_once(source) do
    case detect(source) do
      {:ok, end_line, end_col} ->
        step1 = insert_end_before(source, end_line, end_col)

        if step1 == source do
          # Nothing spliced (the reported column was not a `)`): give up.
          :no_fix
        else
          # Inserting `end` must have left exactly the "extra `end` where the
          # call's `)` should close" error — i.e. there is a stray `end` to
          # remove. (When inserting `end` already parses, this is `:none`: that
          # is NoUnclosedFnDelimiter's case, so the two rules never both fire.)
          # The `(` the error names comes back with it, because that position is
          # the only thing that tells "this stray `end` is gone" apart from
          # "some other `(` in the file is closed by an `end` too".
          case stray_end_error(step1) do
            {:ok, opening} -> delete_stray_end(step1, end_line, opening)
            :none -> :no_fix
          end
        end

      :none ->
        :no_fix
    end
  end

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
  # the enclosing call's `)` was expected. Returns the position of that `(` —
  # the identity of this particular error, which survives the line deletion
  # below unshifted (the `(` is always above the line being deleted).
  defp stray_end_error(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        if stray_end_meta?(meta), do: {:ok, opening_position(meta)}, else: :none

      _ ->
        :none
    end
  end

  defp stray_end_meta?(meta) do
    Keyword.get(meta, :error_type) == :mismatched_delimiter and
      Keyword.get(meta, :opening_delimiter) == :"(" and
      Keyword.get(meta, :closing_delimiter) == :end and
      Keyword.get(meta, :expected_delimiter) == :")"
  end

  defp opening_position(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

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

  # Scanning from the insertion line downward — never back into a docstring
  # *above* it — delete the first bare `end` line whose removal clears the
  # extra-`end` error. The scan direction only bounds where the search starts;
  # what rejects a bare `end` that is string or heredoc content, above or below,
  # is `clears_stray_end?/2`.
  defp remove_stray_end(source, start_idx, opening) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, idx} -> idx >= start_idx and bare_end?(line) end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.find_value(:none, fn idx ->
      candidate = lines |> List.delete_at(idx) |> Enum.join("\n")
      if clears_stray_end?(candidate, idx, opening), do: {:ok, candidate, idx}, else: false
    end)
  end

  defp delete_stray_end(step1, end_line, opening) do
    case remove_stray_end(step1, end_line - 1, opening) do
      {:ok, step2, deleted_idx} -> {:fixed, step2, end_line, deleted_idx + 1}
      :none -> :no_fix
    end
  end

  # Did deleting line `deleted_idx` (0-based) actually remove the stray `end`
  # that `opening` names? Two things must hold, and neither is "the whole file
  # parses now" — that gate declined on any file with a second fault anywhere,
  # this bug's own second copy included.
  #
  #   * The extra-`end` error at that same `(` is gone. Deleting a line that is
  #     heredoc, string or comment content removes no `end` token, so that error
  #     survives byte-for-byte and the candidate is rejected — this, not the
  #     downward scan, is the whole of the rule's masking discipline. Matching
  #     on the `(`'s position rather than on the error's shape matters: a file
  #     can hold an unrelated `(` closed by an `end` of its own (`def f(, do: 1`
  #     is one), and that must not read as "the stray `end` is still there".
  #   * The front end now gets at least as far as the deleted line. Deleting a
  #     real `end` belonging to some enclosing block also clears the extra-`end`
  #     error, but leaves that block unterminated and drags the error back
  #     *above* the repair; `:end_line` is where the front end stopped, which
  #     (unlike `:line`) does not run backwards on progress.
  defp clears_stray_end?(candidate, deleted_idx, opening) do
    case Code.string_to_quoted(candidate, columns: true) do
      {:ok, _ast} ->
        true

      {:error, {meta, _message, _token}} when is_list(meta) ->
        not same_stray_end?(meta, opening) and stopped_at_or_below?(meta, deleted_idx)

      _ ->
        false
    end
  end

  defp same_stray_end?(meta, opening),
    do: stray_end_meta?(meta) and opening_position(meta) == opening

  defp stopped_at_or_below?(meta, deleted_idx) do
    case Keyword.get(meta, :end_line) do
      line when is_integer(line) -> line > deleted_idx
      _ -> false
    end
  end

  defp bare_end?(line), do: Regex.match?(~r/^\s*end\s*$/, line)
end
