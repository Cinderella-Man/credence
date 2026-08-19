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
  the exact `fn`/`)` mismatch — and the stray `end` is found by token position,
  not by trial: it is the first `end` token below the repaired `)`. That search
  runs over `Credence.SourceMask`'s shadow, which is what keeps the rule out of
  strings, heredocs and comments: an `end` that is heredoc *content* is not a
  token, so it neither stops the search nor gets deleted. Deleting it is still
  required to clear the leftover extra-`end` error before the repair is kept.

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
  both fire on the same input. Being local is not the same as being credulous,
  so two things are pinned down before any line is deleted:

    * the extra-`end` complaint must name a `(` **at or above** the line just
      repaired. An unrelated `def f(, do: 1` lower down the file produces an
      identically shaped "`(` closed by `end`" error of its own, and reading
      that as evidence about this repair invents a stray `end` that does not
      exist. It is also what tells the two shapes apart: for the plain
      unclosed-`fn` the insertion balances the code outright, and the only such
      complaint left is somebody else's, below.
    * the line deleted must hold the first `end` **token** below the repair —
      the stray one, by the shape of the bug. Walking past it to a later bare
      `end` line deletes a real terminator, and that can rebalance the file so
      thoroughly that it parses, with the stray `end` silently closing whatever
      block lost its own.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  # Termination is by construction (each pass deletes one line), so this is a
  # bound on *work*, not a correctness guard — matching the sibling rule.
  @max_passes 100

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
  defp repair(source), do: repair(source, [], [], @max_passes)

  defp repair(source, reported, _removed, 0), do: done(source, reported)

  defp repair(source, reported, removed, passes_left) do
    case repair_once(source) do
      {:fixed, fixed, line, deleted_line} ->
        repair(
          fixed,
          [input_line(line, removed) | reported],
          Enum.sort([input_line(deleted_line, removed) | removed]),
          passes_left - 1
        )

      :no_fix ->
        done(source, reported)
    end
  end

  defp done(_source, []), do: :no_fix
  defp done(source, reported), do: {:fixed, source, Enum.reverse(reported)}

  # A line number in the current source, back in the input's numbering: every
  # already-deleted input line at or above it shifted it up by one.
  defp input_line(line, removed) do
    Enum.reduce(removed, line, fn deleted, acc ->
      if deleted <= acc, do: acc + 1, else: acc
    end)
  end

  # Insert the missing `end` before the parser-pinpointed `)`, then delete the
  # stray `end` the shape of the bug leaves behind — provided the parser agrees
  # that a stray `end` of ours is what is now left over.
  defp repair_once(source) do
    case detect(source) do
      {:ok, end_line, end_col} ->
        step1 = insert_end_before(source, end_line, end_col)

        cond do
          # Nothing spliced (the reported column was not a `)`): give up.
          step1 == source ->
            :no_fix

          # Inserting `end` must have left exactly the "extra `end` where the
          # call's `)` should close" error, at a `(` at or above the line just
          # repaired — i.e. there is a stray `end` of *ours* to remove. When
          # inserting `end` already parses there is no such error at all: that
          # is NoUnclosedFnDelimiter's case, so the two rules never both fire.
          # An identically shaped error naming a `(` further down the file
          # belongs to some other fault and is not evidence about this repair.
          not stray_end_above?(step1, end_line) ->
            :no_fix

          true ->
            delete_stray_end(step1, end_line)
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

  # Is the front end's complaint an extra `end` standing where the `)` of a call
  # opened at or above `repair_line` should have closed?
  #
  # This one predicate answers both halves of the decision, which is why it takes
  # the repair's line rather than the `(`'s position: before the deletion it says
  # "there is a stray `end` of ours to remove", and afterwards its negation says
  # "that stray `end` is gone". Asking it about a *position* instead — the `(`
  # seen before the deletion against the `(` reported after it — is not the same
  # question: it also reads "the same fault, now blamed on a different enclosing
  # `(`" as success.
  #
  # The `at or above` half is what keeps an unrelated fault from being mistaken
  # for ours. `def f(, do: 1` lower down the file raises an identically shaped
  # error of its own; treating that as ours makes the rule delete a line on the
  # strength of a signal that says nothing about the repair.
  defp stray_end_above?(source, repair_line) do
    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        stray_end_above_meta?(meta, repair_line)

      _ ->
        false
    end
  end

  defp stray_end_above_meta?(meta, repair_line),
    do: stray_end_meta?(meta) and opening_line(meta) <= repair_line

  defp stray_end_meta?(meta) do
    Keyword.get(meta, :error_type) == :mismatched_delimiter and
      Keyword.get(meta, :opening_delimiter) == :"(" and
      Keyword.get(meta, :closing_delimiter) == :end and
      Keyword.get(meta, :expected_delimiter) == :")"
  end

  # A missing or non-integer line is treated as "below everything", so a meta
  # this rule cannot place never counts as evidence for a deletion.
  defp opening_line(meta) do
    case Keyword.get(meta, :line) do
      line when is_integer(line) -> line
      _ -> :infinity
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

  # Delete the stray `end` — the one the *shape of the bug* puts immediately
  # after the `)` just repaired, which is the first `end` token below that line.
  # Nothing further down is a candidate: a later bare `end` line is some real
  # block's terminator, and deleting one of those can rebalance the file so well
  # that it parses, with the stray `end` quietly closing the block that lost its
  # own — indistinguishable from a repair by any "does it parse" test.
  #
  # It has to be an `end` *token*, so the search runs over the shadow: a bare
  # `end` line that is heredoc, string or comment content is not the stray one
  # and must not stop the search short, nor be deleted. Anything the search does
  # find that is not alone on its line is declined rather than rewritten — the
  # rest of that line is code or a comment this rule has no business editing.
  defp delete_stray_end(step1, end_line) do
    lines = String.split(step1, "\n")

    with {:ok, idx} <- first_end_token_line(step1, end_line),
         true <- bare_end?(Enum.at(lines, idx)),
         candidate = lines |> List.delete_at(idx) |> Enum.join("\n"),
         true <- clears_stray_end?(candidate, idx, end_line) do
      {:fixed, candidate, end_line, idx + 1}
    else
      _ -> :no_fix
    end
  end

  # The first line at index `from_idx` or below carrying an `end` **token**.
  # `SourceMask.lines/1` pairs each line with its shadow, in which every string,
  # heredoc and comment byte is blanked, so an `end` inside one of those is not
  # seen at all. A false positive here (an `:end` atom, say) only ever makes the
  # rule decline, because such a line is never a bare `end` line.
  defp first_end_token_line(source, from_idx) do
    source
    |> SourceMask.lines()
    |> Enum.with_index()
    |> Enum.drop(from_idx)
    |> Enum.find_value(:none, fn {{_line, shadow}, idx} ->
      if Regex.match?(~r/(?<![[:alnum:]_])end(?![[:alnum:]_?!])/, shadow), do: {:ok, idx}
    end)
  end

  # Did deleting line `deleted_idx` (0-based) actually remove the stray `end`?
  # Two things must hold, and neither is "the whole file parses now" — that gate
  # declined on any file with a second fault anywhere, this bug's own second
  # copy included.
  #
  #   * No extra-`end` error is left at or above the repair. Deleting a line that
  #     is heredoc, string or comment content removes no `end` token, so that
  #     error survives byte-for-byte and the candidate is rejected — this, not
  #     where the search starts, is what keeps the rule out of literals. Asking
  #     it of the whole region at or above the repair rather than of one
  #     remembered `(` matters twice over: an unrelated `(` closed by an `end` of
  #     its own further down (`def f(, do: 1`) must not read as "the stray `end`
  #     is still there", and the same fault re-blamed on a different enclosing
  #     `(` above must not read as "it is gone".
  #   * The front end did not stop above the deleted line. This is a cheap
  #     monotonicity check on `:end_line`, no more: it does *not* catch a
  #     deletion that left a block unterminated, because an unclosed delimiter
  #     makes the front end consume the whole file and report EOF (see
  #     `Credence.Syntax.ProgressGuard`, which refuses to compare such a stop at
  #     all). What rules that case out is choosing the line to delete by token
  #     position rather than by searching for one that clears the error.
  defp clears_stray_end?(candidate, deleted_idx, repair_line) do
    case Code.string_to_quoted(candidate, columns: true) do
      {:ok, _ast} ->
        true

      {:error, {meta, _message, _token}} when is_list(meta) ->
        not stray_end_above_meta?(meta, repair_line) and
          stopped_at_or_below?(meta, deleted_idx)

      _ ->
        false
    end
  end

  defp stopped_at_or_below?(meta, deleted_idx) do
    case Keyword.get(meta, :end_line) do
      line when is_integer(line) -> line > deleted_idx
      _ -> false
    end
  end

  defp bare_end?(line) when is_binary(line), do: Regex.match?(~r/^\s*end\s*$/, line)
  defp bare_end?(_line), do: false
end
