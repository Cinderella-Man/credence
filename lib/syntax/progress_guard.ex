defmodule Credence.Syntax.ProgressGuard do
  @moduledoc """
  The Syntax round's per-rule progress measure (docs/12 `C3`).

  The Syntax round is the one round whose input is *by definition* unparseable,
  and whose intermediate states are legitimately unparseable too: a file that
  needs both a `div`/`rem` fix and a keyword-order fix is broken after the first
  repair as well as before it. A naive "must parse after every rule" gate would
  therefore disable the round outright. This module answers the weaker, honest
  question the round can actually enforce:

  > did this rule make the source **worse**?

  Only a demonstrated regression is a revert. "Still broken" is the expected
  state, never a verdict.

  ## What is measured

  `measure/1` reduces a source to a three-part state:

    * `:parses` — `Sourceror.parse_string/1` succeeds. The best state there is.
    * `:parse_error` — it tokenizes, but the parser rejects it.
    * `:tokenize_error` — the *tokenizer* gives up (unterminated string or
      heredoc, unclosed/mismatched delimiter).
    * `:unknown` — the measurement itself failed. Never comparable, never a revert.

  ## Which position

  Deliberately **not** `meta[:line]`. For the whole "missing terminator" family —
  the most common LLM breakage there is — the parser reports the position of the
  *opening* delimiter of the innermost unclosed construct, so closing one moves
  the reported position **backwards**: progress looks like regression. Observed
  on a real fixture, where appending the missing `end` to

      defmodule M do
        def go(list) do
          Enum.each(list, fn item ->
            IO.puts(item)

  moved the report from `3:21` (the `fn`) to `3:14` (the now-innermost `(`) —
  strictly better source, backwards position.

  The position used is `meta[:end_line]/[:end_column]` when present — where the
  front end actually *stopped* — falling back to `line`/`column` when it is not.
  That one is monotone: EOF for an unclosed delimiter (maximal, so nothing about
  the rest of the file can fake progress) and the offending token for everything
  else.

  The tokenize/parse split is not cosmetic. The `evolution` branch rejected 7+
  line-regex Syntax rules for mangling heredoc *content*; that damage shows up
  as a source that no longer tokenizes. Position alone cannot see it — an
  unterminated string is reported at its **opening** line, which is often
  *after* the parse error the round started from, so the position moves
  *forward* while the source gets strictly worse. Stage catches it; position
  does not.

  ## Comparing positions across an edit

  Line numbers on either side of a rewrite are not directly comparable: a rule
  that inserts or deletes lines shifts every position below it without changing
  anything about how far the parser got. So positions are bucketed against the
  rule's own edit, using the common leading and trailing lines of the two
  sources:

    * **prefix** (line ≤ common leading lines) — text the rule did not touch and
      the parser reached *before* the edit. Absolute `{line, column}` compares
      directly.
    * **span** (between the first and last changed line) — the rewritten region.
      Offsets inside it are not comparable (the region has a different length and
      different content on each side), so they are deliberately **not** compared.
    * **suffix** (after the last changed line) — untouched text below the edit.
      Compared by distance from EOF, which is invariant under any line-count
      change the edit made above it.

  Ordering is `prefix < span < suffix`, so the comparison that matters most is
  exactly the one that fires:

      old: parse error at line 12   (below the rule's edit — suffix)
      new: parse error at line 3    (at the rule's edit  — span)

  The parser used to get *past* the line this rule rewrote and now it does not.
  That is the Phase-4 corruption signature (a regex rewrite gluing a call name
  onto its operator, mangling a `&1` capture, editing inside a string literal),
  and it is a revert.

  One position is never compared at all: a stop at **EOF**. An unclosed
  delimiter makes the front end consume the whole file before giving up, so its
  stop position says nothing about where the damage is — and closing that
  delimiter reveals whatever real error sits higher up, which would then read as
  a retreat. Observed on `CloseUnclosedDocHeredoc` closing an `@doc \"\"\"` that had
  swallowed the rest of the file: the repair looked like a regression until EOF
  stops were excluded.

  ## What it deliberately does not catch

  Inside the span nothing is compared, so a rule that rewrites the broken line
  and leaves it broken *differently* is kept — it may still be a step on the way
  to a repair, and the round's all-or-nothing gate is the backstop if it is not.
  Likewise, when the incoming error is already a tokenizer error at line 1 (the
  very common "missing terminator: end", reported at the *opening* `do`), no
  position can be worse than it already is, so only a stage regression is
  visible there.
  """

  @type stage :: :parses | :parse_error | :tokenize_error | :unknown
  @type state :: {stage(), non_neg_integer(), non_neg_integer()}

  @doc """
  Reduces `source` to the state `verdict/4` compares. See the moduledoc.
  """
  # No `is_binary/1` guard: a buggy rule that returns something else must reach
  # the same fate it had before this guard existed (`:unknown`, kept, and it
  # blows up in the caller's own parse), not a new FunctionClauseError here.
  @spec measure(String.t()) :: state()
  def measure(source) do
    case safe_parse(source) do
      {:ok, _ast} ->
        {:parses, 0, 0}

      {:error, {meta, _message, _token}} when is_list(meta) ->
        {line, column} = stop_position(meta)
        {front_end_stage(source), line, column}

      _other ->
        {:unknown, 0, 0}
    end
  end

  @doc """
  A short human-readable rendering of a state, for the revert log line.
  """
  @spec describe(state()) :: String.t()
  def describe({:parses, _, _}), do: "parses"
  def describe({:unknown, _, _}), do: "unmeasurable"
  def describe({stage, line, column}), do: "#{stage} at #{line}:#{column}"

  @doc """
  `:keep` unless `after_source` is demonstrably worse than `before_source`.

  Both states must come from `measure/1` on the corresponding source. The two
  sources are needed as well as the two states because a position is only
  meaningful relative to the text the rule changed.
  """
  @spec verdict(String.t(), state(), String.t(), state()) :: :keep | :revert
  def verdict(before_source, {before_stage, bl, bc}, after_source, {after_stage, al, ac}) do
    cond do
      # Nothing beats a source that parses, and nothing else needs deciding.
      after_stage == :parses ->
        :keep

      # Never revert on ignorance: an unmeasurable state is not evidence.
      before_stage == :unknown or after_stage == :unknown ->
        :keep

      rank(after_stage) < rank(before_stage) ->
        :revert

      rank(after_stage) > rank(before_stage) ->
        :keep

      true ->
        position_verdict(before_source, {bl, bc}, after_source, {al, ac})
    end
  end

  # ── stages ────────────────────────────────────────────────────────────────

  defp rank(:tokenize_error), do: 0
  defp rank(:parse_error), do: 1
  defp rank(:parses), do: 2

  # The source does not parse — did it even tokenize? `:elixir_tokenizer` is an
  # Elixir-internal module, so every failure mode (missing module, changed
  # return shape, invalid UTF-8 in `to_charlist`) degrades to `:unknown`, which
  # `verdict/4` treats as "no evidence" rather than as a regression. The guard
  # loses resolution if this ever breaks; it never invents a revert.
  #
  # Only the leading tag is matched, never the arity: on Elixir 1.20 success is a
  # 6-tuple and failure a 5-tuple, and neither shape is public API. Matching the
  # full tuple silently downgraded every measurement to `:unknown` — caught by
  # the stage test in `test/syntax_round_safety_test.exs`, which is why that test
  # pins the three stages by name.
  defp front_end_stage(source) do
    result = :elixir_tokenizer.tokenize(String.to_charlist(source), 1, [])

    case elem(result, 0) do
      :ok -> :parse_error
      :error -> :tokenize_error
      _other -> :unknown
    end
  rescue
    _ -> :unknown
  catch
    _, _ -> :unknown
  end

  defp safe_parse(source) do
    Sourceror.parse_string(source)
  rescue
    _ -> :unmeasurable
  catch
    _, _ -> :unmeasurable
  end

  # Where the front end stopped, not where the construct it was looking for
  # opened. See the moduledoc — `line`/`column` runs backwards on progress for
  # every unclosed-delimiter error.
  defp stop_position(meta) do
    case {Keyword.get(meta, :end_line), Keyword.get(meta, :end_column)} do
      {line, column} when is_integer(line) and is_integer(column) -> {line, column}
      _ -> {int(Keyword.get(meta, :line)), int(Keyword.get(meta, :column))}
    end
  end

  defp int(n) when is_integer(n) and n >= 0, do: n
  defp int(_), do: 0

  # ── positions ─────────────────────────────────────────────────────────────

  defp position_verdict(before_source, before_pos, after_source, after_pos) do
    old_lines = String.split(before_source, "\n")
    new_lines = String.split(after_source, "\n")
    old_total = length(old_lines)
    new_total = length(new_lines)

    if eof_stop?(before_pos, old_total) or eof_stop?(after_pos, new_total) do
      # A front end that consumed the whole file and only then gave up has said
      # nothing about *where* the damage is, so its position must not be compared
      # with one that points at a token. Every unclosed delimiter stops at EOF,
      # so without this a rule that closes a runaway heredoc — revealing a real
      # error higher up the file, which is exactly the repair — reads as a
      # regression. Observed: `CloseUnclosedDocHeredoc` closing an `@doc """`
      # that had swallowed the rest of the file.
      :keep
    else
      prefix = common_prefix(old_lines, new_lines, 0)
      limit = min(old_total, new_total) - prefix
      suffix = min(common_prefix(Enum.reverse(old_lines), Enum.reverse(new_lines), 0), limit)

      old_key = position_key(before_pos, prefix, suffix, old_total)
      new_key = position_key(after_pos, prefix, suffix, new_total)

      if new_key < old_key, do: :revert, else: :keep
    end
  end

  defp eof_stop?({line, _column}, total_lines), do: line >= total_lines

  # Bigger key = the front end got further. `{0, ...} < {1, ...} < {2, ...}`
  # orders prefix < span < suffix, which is their order in the file.
  defp position_key({line, column}, prefix, suffix, total) do
    cond do
      # Untouched text above the edit: absolute position is comparable.
      line <= prefix -> {0, line, column}
      # Untouched text below the edit: distance from EOF is comparable, and is
      # invariant under any lines the edit added or removed above it.
      line > total - suffix -> {2, line - total, column}
      # Inside the rewritten region: not comparable, and not compared.
      true -> {1, 0, 0}
    end
  end

  defp common_prefix([h | old], [h | new], count), do: common_prefix(old, new, count + 1)
  defp common_prefix(_, _, count), do: count
end
