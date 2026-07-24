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

  Three guards keep the repair honest, and `analyze/1` and `fix/1` share them
  (`repair/1`), so the rule never flags what it will not fix:

    * **The result must parse.** A repair is committed only when the *whole*
      source parses afterwards. This drops guesses like

          x = {1, 2
          IO.puts(x)
        end

      where the missing `}` could belong on either line — appending it before
      the `end` yields `{1, 2 IO.puts(x)}`, which does not parse, so the rule
      stays silent rather than picking a placement.

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
  leave an unmatched `}`, so that number is unique.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

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
         {:ok, fixed} <- close_at(lines, index) do
      {:fixed, fixed, open_line}
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
             is_integer(open_line) and is_integer(end_line) and end_line > open_line do
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
    line = Enum.at(lines, index)

    Enum.find_value(1..@max_braces, :none, fn count ->
      candidate =
        lines
        |> List.replace_at(index, line <> String.duplicate("}", count))
        |> Enum.join("\n")

      if match?({:ok, _}, Code.string_to_quoted(candidate)), do: {:ok, candidate}
    end)
  end
end
