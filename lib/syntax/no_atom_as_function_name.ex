defmodule Credence.Syntax.NoAtomAsFunctionName do
  @moduledoc """
  Drops the leading colon from an atom used in call position — `:helper(x)` becomes
  `helper(x)`.

  An atom followed by `(` is never legal Elixir, so the tokenizer stops at the `(`
  and the **whole file** fails to parse. Nothing downstream sees it: no compiler
  warning, no Semantic diagnostic, no Pattern check — the generated module simply
  does not compile.

  The observed shape is an Erlang module-colon carried onto a *local* function
  name. Both field samples come from one generated file:

      :ets_table_name(__MODULE__)
      :ets.whereis(:ets_table_name(name))

  The second is the instructive one. `:ets.whereis` is correct and must be left
  alone; only the inner `:ets_table_name` is wrong. The parser reports the inner
  `(` first, so acting at its position repairs exactly the right colon.

  ## How it decides, and why not by regex

  Both callbacks go through `locate/1`, which asks the **parser** where the file
  stops and then requires three things of that exact position:

    1. the error token is `'('`,
    2. the character at the reported column really is `(`, and
    3. the text immediately before it ends in a bare atom, `~r/(?<!\\w):\\w+[?!]?$/`.

  This is what the rejected implementation got wrong: it scanned the whole source
  with `Regex.replace`, and a `:word(` inside a string, a comment or a heredoc looks
  identical to the real thing. Keying on the parser's own stopping point removes the
  question — a decoy in a string cannot be where parsing failed, because a string
  containing `:helper(1)` parses fine.

  ## Scope

  `\\w+` with an optional trailing `?`/`!` is the whole atom vocabulary this rule
  will touch, and each exclusion is because dropping the colon does **not** produce
  valid code (executed, not assumed):

      :valid?(1)     -> valid?(1)      parses    — covered
      :save!(1)      -> save!(1)       parses    — covered
      :"my fun"(1)   -> "my fun"(1)    does not  — declined
      :+(1, 2)       -> +(1, 2)        does not  — declined

  A quoted atom and an operator atom are the same failure mode, but there is no
  one-character repair for either, so they are left for a human. `check` declines
  them too — reporting what the fix will not repair is what
  `test/fix_or_drop_test.exs` exists to prevent.

  **Every occurrence is repaired in one `fix/1` call, and it has to be.** The
  Syntax round is a single `Enum.reduce` over the rules (`lib/syntax.ex:93`) — each
  `fix/1` is called exactly once, there is no repeat-until-fixpoint loop — and
  `commit_or_roll_back/4` then discards the WHOLE round's work if the result still
  does not parse. So a rule that repaired one colon per call would repair nothing at
  all on a file with two: measured, the round came back
  `{NoAtomAsFunctionName, :rolled_back}` with the file byte-identical. `repairs/1`
  therefore loops, re-asking the parser after each edit rather than guessing where
  the next one is.

  It terminates because every edit removes exactly one byte, so the source is
  strictly shorter each time.

  ## Bad (won't parse — syntax error before `'('`)

      def table(name), do: :ets_table_name(name)

  ## Good

      def table(name), do: ets_table_name(name)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # A bare atom, immediately before the offending `(`. `(?<!\w)` stops it matching
  # the tail of `::` in a typespec or of a word already ending in a colon.
  @bare_atom ~r/(?<!\w):\w+[?!]?$/u

  @impl true
  def analyze(source) do
    {_repaired, lines} = repairs(source)

    Enum.map(lines, fn line ->
      %Issue{
        rule: :no_atom_as_function_name,
        message:
          "an atom in call position (`:name(...)`) is not valid Elixir and stops the " <>
            "parser, so nothing in the file compiles. Drop the leading colon.",
        meta: %{line: line}
      }
    end)
  end

  @impl true
  def fix(source) do
    {repaired, _lines} = repairs(source)
    repaired
  end

  # The one loop both callbacks share, so they cannot disagree about how many
  # occurrences there are: `{repaired_source, [line_of_each_repair]}`.
  defp repairs(source), do: repairs(source, [])

  defp repairs(source, acc) do
    case locate(source) do
      {:ok, line, _column, offset} ->
        repairs(drop_colon(source, line, offset), [line | acc])

      :none ->
        {source, Enum.reverse(acc)}
    end
  end

  # Ask the parser where the file stops, then confirm the position is this defect.
  # Returns the 0-based offset of the colon within its line.
  defp locate(source) do
    with {:error, {meta, _msg, "'('"}} <- Sourceror.parse_string(source),
         line_no when is_integer(line_no) <- Keyword.get(meta, :line),
         column when is_integer(column) <- Keyword.get(meta, :column),
         line = Enum.at(String.split(source, "\n"), line_no - 1, ""),
         "(" <- String.at(line, column - 1),
         [{offset, _len} | _] <-
           Regex.run(@bare_atom, String.slice(line, 0, column - 1), return: :index) do
      {:ok, line_no, column, offset}
    else
      _ -> :none
    end
  end

  defp drop_colon(source, line_no, offset) do
    lines = String.split(source, "\n")
    line = Enum.at(lines, line_no - 1)
    <<before::binary-size(^offset), ?:, suffix::binary>> = line
    without = before <> suffix

    lines
    |> List.replace_at(line_no - 1, without)
    |> Enum.join("\n")
  end
end
