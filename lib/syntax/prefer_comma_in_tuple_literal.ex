defmodule Credence.Syntax.PreferCommaInTupleLiteral do
  @moduledoc """
  Repairs the LLM syntax error where the comma after a tuple's leading atom is
  missing — `{:noreply state}` instead of `{:noreply, state}`.

  It is the most common shape of the mistake by far, because the two elements
  read as one phrase (`:noreply state`, `:reply reply`) and the missing
  separator is invisible in prose. Elixir stops at the element that should have
  followed the comma with `syntax error before: state`. The repair is a single
  `,` inserted directly after the atom; nothing is moved, deleted or
  re-indented, and the whitespace that already separates the two elements is
  kept as it was, so a tuple spread over two lines stays spread over two lines.

  ## Bad (won't parse — syntax error before: state)

      {:noreply state}

  ## Good

      {:noreply, state}

  ## Which gap gets the comma

  Only the one the parser's own error position points at.
  `Code.string_to_quoted/2` reports this error at the exact line and column of
  the element that follows the missing comma, and the rule walks back from
  there: over blanks (a newline counts, so a tuple broken across lines is still
  found), then over the atom's name, and it proceeds only if what it lands on is
  a `:name` sitting immediately behind a `{`.

  That anchor is what keeps strings, heredocs, comments and sigils safe. The
  syntax phase runs every rule's `fix/1` over any source that fails to parse —
  including a file that fails for an entirely unrelated reason and merely
  *contains* the text `{:ok result}` in a docstring or a comment. The parser
  never blames a position inside those, so this rule never edits one; the
  previous, regex-driven version of this rule did, which is why the position is
  taken from the parser rather than from a scan.

  ## What it refuses to touch

  `analyze/1` reports exactly what `fix/1` rewrites — both run the same search —
  so nothing is flagged as a problem the fix then declines to solve. The rule
  stays silent unless all of these hold:

    * the source's *first* parse error is a `syntax error before:`, and walking
      back from the blamed position over blanks lands on the end of a lowercase
      atom (`:noreply`, `:_private`) that is itself preceded by `{`;

    * the character in front of that `{` does not turn it into something other
      than a tuple. `%{:ok state}` is a map (`%{:ok, state}` would parse but not
      compile — a map wants pairs), `%Foo{`, `~w{`, `Foo.{` and `\#{` are a
      struct, a sigil, an alias multi-import and an interpolation; all are left
      alone;

    * inserting the comma makes the **whole file** parse. This is the check that
      turns "probably the right gap" into "known to be": a blamed token that
      merely happens to sit behind an atom (`{:ok ->  x}`) yields output that
      still does not parse, and is therefore reported as no issue and left
      byte-identical rather than swapped for a different syntax error.

  A file holding several of these is repaired in one go: after each insertion
  the source is re-parsed and the next blamed gap repaired, and the result is
  handed back only once the file parses. If a repair the rule cannot account for
  is left over — an unrelated error elsewhere in the file — it returns the
  source untouched and leaves the file to the rule that owns that error.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "syntax error before"

  @blanks [" ", "\t", "\n", "\r", "\f", "\v"]

  # A `{` directly behind one of these is not a tuple's: `%{` / `%Foo{` (map,
  # struct), `~w{` (sigil), `Foo.{` (alias multi), `#{` (interpolation or a
  # comment), `?{` (a char literal). Letters and digits also cover every other
  # sigil name.
  @not_a_tuple_before_brace ~r/[A-Za-z0-9_.%#?]/

  @name_char ~r/[A-Za-z0-9_]/

  @name_start ~r/[a-z_]/

  # Every accepted insertion moves the parser's first error strictly forward, so
  # this only bounds a pathological file; it is not a cap on how many commas a
  # normal file may be missing.
  @max_repairs 100

  @impl true
  def analyze(source) do
    case locate(source) do
      {:ok, line, _repaired} ->
        [
          %Issue{
            rule: :prefer_comma_in_tuple_literal,
            message:
              "Missing comma after the atom in a tuple literal — the parser stops at the " <>
                "element that should follow it. Separate the elements: `{:noreply, state}`.",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case locate(source) do
      {:ok, _line, repaired} -> repaired
      :none -> source
    end
  end

  # Single source of truth for both callbacks: either there is a gap to fill —
  # and the file is known to parse once every such gap is filled — or there is
  # nothing to report. Never returns a half-repaired source.
  defp locate(source), do: repair(source, nil, @max_repairs)

  defp repair(_source, _first_line, 0), do: :none

  defp repair(source, first_line, budget) do
    case insert_one(source) do
      :none ->
        :none

      {:ok, line, repaired} ->
        first_line = first_line || line

        case Code.string_to_quoted(repaired, emit_warnings: false) do
          {:ok, _ast} -> {:ok, first_line, repaired}
          {:error, _} -> repair(repaired, first_line, budget - 1)
        end
    end
  end

  # One comma, at the gap the parser is currently blaming.
  defp insert_one(source) do
    lines = String.split(source, "\n")

    with {:error, {meta, message, _token}} <-
           Code.string_to_quoted(source, columns: true, emit_warnings: false),
         true <- is_list(meta),
         line when is_integer(line) <- Keyword.get(meta, :line),
         col when is_integer(col) <- Keyword.get(meta, :column),
         true <- String.contains?(message_text(message), @error_fragment),
         {:ok, blamed} <- char_index(lines, line, col),
         chars = source_chars(lines),
         {:ok, atom_end} <- atom_gap_before(chars, blamed) do
      {:ok, line, insert_comma(chars, atom_end)}
    else
      _ -> :none
    end
  end

  # Some parser errors carry a `{prefix, suffix}` pair instead of a plain binary;
  # both have to survive the fragment test without raising.
  defp message_text(message) when is_binary(message), do: message
  defp message_text({prefix, suffix}), do: to_string(prefix) <> to_string(suffix)
  defp message_text(other), do: inspect(other)

  # The parser counts columns in graphemes, not bytes and not codepoints: a
  # combining accent, a ZWJ emoji and a flag are each one column (checked in the
  # tests). Splitting the line list back into graphemes and re-inserting the
  # "\n" the split removed gives one flat list whose offsets line up with the
  # parser's, and whose `Enum.join/1` is the original source byte for byte —
  # including a CRLF line ending, whose "\r" stays on its own line's tail.
  defp source_chars(lines) do
    lines
    |> Enum.map(&String.graphemes/1)
    |> Enum.intersperse(["\n"])
    |> List.flatten()
  end

  defp char_index(lines, line, col) when line >= 1 and col >= 1 do
    if line <= length(lines) do
      offset =
        lines
        |> Enum.take(line - 1)
        |> Enum.reduce(0, fn text, acc -> acc + length(String.graphemes(text)) + 1 end)

      {:ok, offset + col - 1}
    else
      :none
    end
  end

  defp char_index(_lines, _line, _col), do: :none

  # Walk back from the blamed element: blanks, then the atom's name, then the
  # `:` and the `{` that must sit behind it. Answers with the index of the
  # atom's last character — the gap goes right after it.
  defp atom_gap_before(chars, blamed) do
    atom_end = skip_back(chars, blamed - 1, &(&1 in @blanks))
    name_start = skip_back(chars, atom_end, &Regex.match?(@name_char, &1)) + 1

    with true <- atom_end < blamed - 1,
         true <- name_start <= atom_end,
         true <- at(chars, name_start - 1) == ":",
         true <- matches?(at(chars, name_start), @name_start),
         true <- at(chars, name_start - 2) == "{",
         false <- matches?(at(chars, name_start - 3), @not_a_tuple_before_brace) do
      {:ok, atom_end}
    else
      _ -> :none
    end
  end

  defp skip_back(chars, index, keep?) when index >= 0 do
    case at(chars, index) do
      nil -> index
      char -> if keep?.(char), do: skip_back(chars, index - 1, keep?), else: index
    end
  end

  defp skip_back(_chars, index, _keep?), do: index

  defp at(_chars, index) when index < 0, do: nil
  defp at(chars, index), do: Enum.at(chars, index)

  defp matches?(nil, _regex), do: false
  defp matches?(char, regex), do: Regex.match?(regex, char)

  # Only the comma is added. Every other character, the blank that already
  # separated the elements included, survives untouched, so line numbering and
  # indentation are what they were.
  defp insert_comma(chars, atom_end) do
    Enum.join(Enum.take(chars, atom_end + 1)) <> "," <> Enum.join(Enum.drop(chars, atom_end + 1))
  end
end
