defmodule Credence.Syntax.NoMapArrowSyntaxInTupleBrace do
  @moduledoc """
  Repairs the LLM syntax error where map arrow syntax (`=>`) is written inside
  bare tuple braces — `{"key" => value}` instead of `%{"key" => value}`.

  The `=>` operator is only valid inside a `%{...}` map literal; bare `{...}` is
  tuple syntax and does not support it, so the parser stops at the arrow with
  `syntax error before: '=>'`. The repair is a single `%` inserted in front of
  the brace that opened the container. One character is added; nothing is moved,
  deleted or re-indented.

  ## Bad (won't parse — syntax error before: '=>')

      Jason.encode!({"error" => "File too large", "max_bytes" => 5_242_880})

  ## Good

      Jason.encode!(%{"error" => "File too large", "max_bytes" => 5_242_880})

  ## Which brace gets the `%`

  Only the one the parser's own error position points at. `Code.string_to_quoted/2`
  reports this error at the exact line and column of the offending `=>`, and the
  rule then walks backwards from that position for the nearest `{`. An arrow
  inside a string, a heredoc, a comment or a sigil can therefore never start a
  repair, because the parser never blames it: it is not a token.

  That anchor alone is not enough, because the syntax phase runs every rule's
  `fix/1` over any source that fails to parse — including a file that fails for
  an unrelated reason and merely *contains* well-formed arrows in a docstring or
  a `%{...}` literal. Those arrows are never the first parse error of such a
  file, so this rule leaves them alone.

  ## What it refuses to touch

  `analyze/1` reports exactly what `fix/1` rewrites — both run the same search —
  so nothing is flagged as a problem the fix then declines to solve. The rule
  stays silent unless all of these hold:

    * the source's *first* parse error is `syntax error before: '=>'`, and the
      blamed position really holds an `=>`;
    * there is a `{` somewhere before that arrow;
    * inserting `%` in front of that brace makes the **whole file** parse, and
      produces a real map literal at the very line and column that was edited.
      This is what rejects a brace that is not the container's (`{"a{b" => 1}`),
      a brace that is already a map's (`%%{` never parses) and a struct's
      (`%Foo%{` never parses);
    * every element of the map that appears is a key/value pair. `%{...}` parses
      happily with a stray non-pair element (`{"a" => 1, b}` would become
      `%{"a" => 1, b}`, which parses but fails to compile), so that shape is
      reported as no issue and left byte-identical rather than repaired into
      code that still does not build.

  A file holding more than one of these is repaired only if the first repair
  makes the whole file parse; otherwise the rule declines rather than edit a
  file whose remaining errors it cannot account for.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "syntax error before"
  @arrow_token "'=>'"

  @impl true
  def analyze(source) do
    case locate(source) do
      {:ok, line, _repaired} ->
        [
          %Issue{
            rule: :no_map_arrow_syntax_in_tuple_brace,
            message:
              "Map arrow `=>` inside tuple braces — it is only valid inside a `%{...}` " <>
                "literal. Write the container as a map: `%{key => value}`.",
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

  # Single source of truth for both callbacks: either there is a brace to turn
  # into `%{` — and the resulting file is known to parse into a map of pairs at
  # that exact spot — or there is nothing to report.
  defp locate(source) do
    lines = String.split(source, "\n")

    with {:error, {meta, message, @arrow_token}} <-
           Code.string_to_quoted(source, columns: true, emit_warnings: false),
         true <- is_list(meta),
         line when is_integer(line) <- Keyword.get(meta, :line),
         col when is_integer(col) <- Keyword.get(meta, :column),
         true <- String.contains?(message_text(message), @error_fragment),
         {:ok, chars} <- line_chars(lines, line),
         true <- arrow_at?(chars, col),
         {:ok, brace_line, brace_col} <- find_open_brace(lines, line, col),
         repaired = insert_percent(lines, brace_line, brace_col),
         {:ok, ast} <-
           Code.string_to_quoted(repaired, columns: true, emit_warnings: false),
         true <- map_of_pairs_at?(ast, brace_line, brace_col) do
      {:ok, brace_line, repaired}
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
  # tests). `String.graphemes/1` splits the same way, so the offsets line up.
  defp line_chars(lines, line) when line >= 1 do
    case Enum.at(lines, line - 1) do
      nil -> :none
      text -> {:ok, String.graphemes(text)}
    end
  end

  defp line_chars(_lines, _line), do: :none

  defp arrow_at?(chars, col) when col >= 1 do
    Enum.at(chars, col - 1) == "=" and Enum.at(chars, col) == ">"
  end

  defp arrow_at?(_chars, _col), do: false

  # Nearest `{` before the blamed arrow: the rest of the arrow's own line first,
  # then whole earlier lines, so a container opened on a previous line is still
  # found. Whether the brace really is the container's is settled by the
  # re-parse, not here.
  defp find_open_brace(lines, line, col) do
    prefix = lines |> Enum.at(line - 1) |> String.graphemes() |> Enum.take(col - 1)

    case last_brace_index(prefix) do
      nil -> search_earlier_lines(lines, line - 1)
      index -> {:ok, line, index + 1}
    end
  end

  defp search_earlier_lines(_lines, 0), do: :none

  defp search_earlier_lines(lines, line) do
    chars = lines |> Enum.at(line - 1) |> String.graphemes()

    case last_brace_index(chars) do
      nil -> search_earlier_lines(lines, line - 1)
      index -> {:ok, line, index + 1}
    end
  end

  defp last_brace_index(chars) do
    chars
    |> Enum.with_index()
    |> Enum.reduce(nil, fn {grapheme, index}, last ->
      if grapheme == "{", do: index, else: last
    end)
  end

  # Insert the single `%` in front of the brace. Only that line changes, and it
  # keeps its length in lines, so every other line's numbering survives the
  # re-parse and the map literal lands on the brace's original column.
  defp insert_percent(lines, line, col) do
    chars = lines |> Enum.at(line - 1) |> String.graphemes()

    repaired_line =
      Enum.join(Enum.take(chars, col - 1)) <> "%" <> Enum.join(Enum.drop(chars, col - 1))

    lines
    |> List.replace_at(line - 1, repaired_line)
    |> Enum.join("\n")
  end

  # The repaired source must hold a map literal at the very line and column the
  # `%` was inserted at, and that map's elements must all be key/value pairs —
  # a bare element (`%{"a" => 1, b}`) parses but does not compile, so it is not
  # a repair.
  defp map_of_pairs_at?(ast, line, col) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:%{}, meta, args} = node, found? when is_list(args) ->
          {node,
           found? or
             (Keyword.get(meta, :line) == line and Keyword.get(meta, :column) == col and
                Enum.all?(args, &match?({_key, _value}, &1)))}

        node, found? ->
          {node, found?}
      end)

    found?
  end
end
