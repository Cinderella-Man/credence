defmodule Credence.Syntax.CloseUnclosedBrace do
  @moduledoc """
  Repairs an unclosed `{` (tuple, map or struct literal) that the LLM left
  dangling, so the parser met `end` where it expected `}`.

  ## Bad (won't parse — mismatched delimiter)

      def init(_opts) do
        {:ok, %{key: "value"}
      end

  ## Good

      def init(_opts) do
        {:ok, %{key: "value"}}
      end

  Detection is driven by the parser itself: `Code.string_to_quoted/2` reports
  the exact `{`/`end` mismatch, so the rule never reacts to a `{` inside a
  string, heredoc, sigil or comment, and a file unparseable for an unrelated
  reason is left untouched.

  ## The safe core

  The parser tells us *which* `{` was left open and *where* the `end` that
  tripped over it sits — but not where the missing `}` belonged. Only one
  placement is faithful: at the very end of the literal's last line, i.e. the
  last non-blank line before that `end`. Everything the tokenizer had already
  swallowed into the literal then stays inside it, in order, and the only
  characters added are the missing `}`s.

  Four guards keep the repair honest, and `analyze/1` and `fix/1` share them
  (`repair/1`), so the rule never flags what it will not fix:

    * **The result must parse.** A repair is committed only when the *whole*
      source parses afterwards. This drops guesses like

          x = {1, 2
          IO.puts(x)
        end

      where the missing `}` could belong on either line — appending it before
      the `end` yields `{1, 2 IO.puts(x)}`, which does not parse, so the rule
      stays silent rather than picking a placement.

    * **The placement must be beyond doubt.** Even a parsing repair is refused
      when appending the `}` to an *earlier* line of the literal would make
      the source parse too. In

          x = {1, 2
          |> IO.inspect()
        end

      the source reads either as the pipe `{1, 2} |> IO.inspect()` or as the
      tuple `{1, 2 |> IO.inspect()}`; both parse, so committing either would
      silently pick one of two meanings. A line ending in `,` is no competing
      placement — closing after a trailing comma drops an element (see below),
      so the comma pins the next line inside the literal. That is a comma in
      *code*: one inside a comment or a string is prose, and the line is probed
      like any other. When the repair needs more than one `}`, a competing
      reading can also *split* them — some on an earlier line, the rest on the
      last — and those placements are tried too. The parser names only the
      *innermost* `{` it was still holding, so when a literal's openings sit on
      different lines the scan walks back out to the line the literal really
      opens on before it starts; otherwise the lines between the two openings
      would never be tried.

      The last line is weighed the same way *within itself*, because the doubt
      does not depend on where the author broke the line: `x = {1, 2 |>
      IO.inspect()` on one line is the same two readings as the example above,
      and only a placement tried inside that line can see it.

    * **No dangling comma.** A literal whose last line ends in `,` is truncated
      mid-element; Elixir accepts a trailing comma, so closing

          {:ok,
        end

      would parse as the *one*-element `{:ok}` — silently dropping an element.
      Such sources are left alone.

    * **The `end` must be on a later line** than the `{`. A same-line
      `x = {1, 2 end` gives us no line to append to, and is left alone.

  The smallest number of `}` that makes the source parse is used, which repairs
  nested openings (`{:ok, %{a: 1` needs two) in one pass. Adding any more would
  leave an unmatched `}`, so that number is unique. `@max_braces` caps that
  number at five: a literal that would need six or more closers is a degenerate
  input, and is refused like the cases above rather than repaired.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  # `{:ok, %{a: %{b: 1` and deeper — a backstop, not a target.
  @max_braces 5

  @impl true
  def analyze(source) do
    case repair(source) do
      {:fixed, _fixed, line} ->
        [
          %Issue{
            rule: :close_unclosed_brace,
            message:
              "Unclosed `{` delimiter — a tuple or map literal is missing its closing `}` before `end`.",
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

  # Single source of truth for both callbacks: either we have a repair that
  # parses, or there is nothing to report.
  defp repair(source) do
    with {:ok, open_line, end_line} <- detect(source),
         {:ok, lines, index} <- target_line(source, open_line, end_line),
         {:ok, fixed, count} <- close_at(lines, index),
         start_line = outermost_open_line(lines, index, open_line, count),
         :ok <- sole_placement(lines, start_line, index, count) do
      {:fixed, fixed, start_line}
    else
      _ -> :no_fix
    end
  end

  # Ask the parser whether a `{` was closed by `end` instead of `}`, and where
  # the two sit.
  defp detect(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        open_line = Keyword.get(meta, :line)
        end_line = Keyword.get(meta, :end_line)

        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == :"{" and
             Keyword.get(meta, :expected_delimiter) == :"}" and
             Keyword.get(meta, :closing_delimiter) == :end and
             is_integer(open_line) and is_integer(end_line) do
          {:ok, open_line, end_line}
        else
          :none
        end

      _ ->
        :none
    end
  end

  # The last non-blank line between the `{` and the `end`, which is where the
  # missing `}` belongs. A line ending in `,` means a truncated element, not a
  # missing `}` — refuse it.
  #
  # This is also the sole enforcer of "the `end` must be on a later line": the
  # scan range is non-empty exactly when `end_line > open_line`, so a same-line
  # `x = {1, 2 end` finds no target line and is refused here. `detect/1` used to
  # repeat that comparison as a guard; it never once changed an answer, so the
  # decision now lives in one place rather than two.
  defp target_line(source, open_line, end_line) do
    lines = String.split(source, "\n")

    index =
      (end_line - 2)..(open_line - 1)//-1
      |> Enum.find(fn index ->
        String.trim(Enum.at(lines, index, "")) != ""
      end)

    cond do
      index == nil -> :none
      String.ends_with?(String.trim_trailing(Enum.at(lines, index)), ",") -> :none
      true -> {:ok, lines, index}
    end
  end

  # Append the fewest `}` that make the whole source parse. Committing only a
  # parsing result is what keeps ambiguous placements out.
  defp close_at(lines, index) do
    Enum.find_value(1..@max_braces, :none, fn count ->
      candidate = candidate(lines, index, count)

      if match?({:ok, _}, Code.string_to_quoted(candidate)), do: {:ok, candidate, count}
    end)
  end

  # The source with `count` `}` appended to the line at `index`.
  defp candidate(lines, index, count) do
    lines
    |> List.replace_at(index, Enum.at(lines, index) <> String.duplicate("}", count))
    |> Enum.join("\n")
  end

  # `detect/1` learns the *innermost* `{` left open, because the parser raises
  # against the top of its delimiter stack. When a literal's openings sit on
  # different lines that is not where the literal starts, and every line above
  # it would go untested as a competing `}` placement. Each `}` appended at the
  # target line closes one more opening, so re-asking the parser with one, two,
  # ... `}` already in place walks back out through the stack; the earliest line
  # any of those answers names is the line the literal really opens on.
  defp outermost_open_line(lines, index, open_line, count) do
    Enum.reduce(1..(count - 1)//1, open_line, fn taken, earliest ->
      case Code.string_to_quoted(candidate(lines, index, taken), columns: true) do
        {:error, {meta, _message, _token}} when is_list(meta) ->
          reported = Keyword.get(meta, :line)

          if Keyword.get(meta, :error_type) == :mismatched_delimiter and
               Keyword.get(meta, :opening_delimiter) == :"{" and is_integer(reported) do
            min(earliest, reported)
          else
            earliest
          end

        _ ->
          earliest
      end
    end)
  end

  # A `}` placed anywhere else in the literal must not also produce a parsing
  # source — when it would (e.g. the next line starts with `|>`), the `}`
  # genuinely belongs in either place and committing one would silently pick
  # one of two meanings. Two families of rival placements are weighed: the end
  # of each earlier line of the literal, and the inside of the target line
  # itself.
  defp sole_placement(lines, start_line, index, count) do
    if earlier_line_placement?(lines, start_line, index, count) or
         mid_line_placement?(lines, index, count) do
      :ambiguous
    else
      :ok
    end
  end

  # A line ending in `,` is no competing placement: closing after a trailing
  # comma drops an element (the same reasoning as target_line/3), so the comma
  # pins the next line inside the literal. That reasoning only holds for a
  # comma in *code* — a comment or string ending in one is prose, and the same
  # comment would swallow the probe's `}` too — so the test is made against the
  # shadow, where everything that is not code has been blanked out.
  defp earlier_line_placement?(lines, start_line, index, count) do
    shadow = lines |> Enum.join("\n") |> SourceMask.mask() |> String.split("\n")

    Enum.any?((start_line - 1)..(index - 1)//1, fn earlier ->
      line = String.trim_trailing(Enum.at(lines, earlier))
      code = String.trim_trailing(Enum.at(shadow, earlier, ""))

      line != "" and not String.ends_with?(code, ",") and
        competing_placement?(lines, earlier, index, count)
    end)
  end

  # The target line's own interior is a placement too. The scan above only ever
  # appends to the *end* of lines above the target, so a literal that opens on
  # the very line the `}` is appended to would meet no guard at all, and a `}`
  # belonging before a trailing operator (`x = {1, 2 |> f()`) would be
  # committed as `{1, f(2)}` where `{1, 2} |> f()` reads just as well. Each
  # position inside the line is tried, with the braces shared between it and
  # the end of the line exactly as `competing_placement?/4` shares them between
  # two lines.
  #
  # No masking is needed here: braces inserted inside a string, charlist or
  # comment close nothing, so such a candidate is left short of `count` closers
  # and cannot parse — `count` being the fewest that make the source parse.
  defp mid_line_placement?(lines, index, count) do
    line = Enum.at(lines, index)
    repaired = candidate(lines, index, count)

    Enum.any?(0..(String.length(line) - 1)//1, fn at ->
      Enum.any?(1..count//1, fn taken ->
        source = insert_and_close(lines, index, at, taken, count - taken)

        source != repaired and match?({:ok, _}, Code.string_to_quoted(source))
      end)
    end)
  end

  # The source with `taken` `}` spliced into the target line at grapheme
  # position `at` and `rest` of them appended to its end.
  defp insert_and_close(lines, index, at, taken, rest) do
    {before, after_} = String.split_at(Enum.at(lines, index), at)

    lines
    |> List.replace_at(index, before <> String.duplicate("}", taken) <> after_)
    |> candidate(index, rest)
  end

  # A competing reading closes the same openings, so it appends exactly as many
  # `}` as the repair did — only their *share* between the earlier line and the
  # target line differs. Those `count` shares are the whole alternative set, so
  # there is no need to try every count on every line; that is what keeps the
  # scan off 25 whole-source reparses for each line of the literal.
  #
  # Unless the braces never reach the code at all. A line ending in a comment,
  # string or heredoc swallows whatever is appended to it, and then there is no
  # telling whether the `}` belonged there — doubt of the same kind, so such a
  # line is refused too. Appending one brace to it *on top of* the full repair
  # is the probe: that only parses when the extra one was swallowed.
  defp competing_placement?(lines, earlier, index, count) do
    Enum.any?(count..1//-1, fn taken ->
      parses_with?(lines, earlier, taken, index, count - taken)
    end) or parses_with?(lines, earlier, 1, index, count)
  end

  # Does the source parse with `taken` `}` appended to the earlier line and
  # `rest` of them appended to the target line?
  defp parses_with?(lines, earlier, taken, index, rest) do
    source =
      lines
      |> List.replace_at(earlier, Enum.at(lines, earlier) <> String.duplicate("}", taken))
      |> candidate(index, rest)

    match?({:ok, _}, Code.string_to_quoted(source))
  end
end
