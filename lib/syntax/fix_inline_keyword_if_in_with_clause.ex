defmodule Credence.Syntax.FixInlineKeywordIfInWithClause do
  @moduledoc """
  Repairs the common LLM syntax error where a keyword-syntax `if`
  (`do:`/`else:`) is used bare as the value of a `<-` binding — typically a
  `with` clause — where the parser cannot tell the `if`'s option commas from
  the enclosing clause's own commas.

  The fix is the one the parser itself asks for everywhere else: wrap the `if`
  in parentheses. Nothing is moved, deleted or re-indented, so the repaired
  code binds exactly the expression that was written, in the same position,
  with the same `else`-clause behaviour.

  ## Bad (won't parse)

      with {:ok, items} <- parse(list),
           ref <- if item_ref(opts), do: item_ref(opts), else: nil,
           parent <- if parent_ref(opts), do: parent_ref(opts), else: nil do
        {:ok, items, ref, parent}
      end

  ## Good

      with {:ok, items} <- parse(list),
           ref <- (if item_ref(opts), do: item_ref(opts), else: nil),
           parent <- (if parent_ref(opts), do: parent_ref(opts), else: nil) do
        {:ok, items, ref, parent}
      end

  ## The two errors this shape produces

  Which parse error you get depends on where the offending binding sits:

    * a binding followed by another one ends with a comma, and the parser
      reports **"unexpected expression after keyword list"** at the column of
      that comma — the comma is exactly where the `if`'s keyword list ended, so
      that is where the closing paren goes;
    * the **last** binding ends with the block's `do`, and the parser reports
      **"unexpected comma… ambiguity in nested calls"** at the column of the
      `<-` — there the closing paren goes just before the trailing `do`.

  Both anchors come from the parser, never from a guess about which line looks
  wrong, and the span between them is handed back to the parser before anything
  is written: it only counts if it parses on its own as an `if` whose options
  are `do:` (and optionally `else:`) and nothing else. A binding whose `if` is
  continued on the next line, or a line with a trailing comment after `do`, has
  no anchor pair the rule can prove and is left alone rather than guessed at.

  One `with` can hold several of these; each rewrite is re-detected from
  scratch, so the file is repaired one proven span at a time.

  ## What it refuses to touch

    * the same errors raised by anything that is not an `if` bound with `<-`
      (`foo(1, key: 2, 3)`, a bare `for` in a container — a sister rule's job);
    * a span that does not parse as a complete keyword-syntax `if`, including
      when the `<-` or the `if` the rule found turns out to be text inside a
      string or a comment;
    * anything at all when the source already parses — `analyze/1` reports
      exactly the spans `fix/1` will wrap, and nothing else.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # A binding that is followed by another one: the parser stops at the comma
  # that closed the `if`'s keyword list.
  @kwlist_fragment "unexpected expression after keyword list"

  # The last binding, terminated by the block's `do`: the parser stops at the
  # `<-` itself.
  @nested_fragment "Parentheses are required to solve ambiguity in nested calls"

  @impl true
  def analyze(source) do
    case locate(source) do
      {:ok, line, _start_col, _end_col} ->
        [
          %Issue{
            rule: :fix_inline_keyword_if_in_with_clause,
            message:
              "Keyword-syntax `if` used bare as a `<-` binding — wrap it in " <>
                "parentheses so its `do:`/`else:` commas are not read as clause separators.",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source), do: rewrite(source)

  defp rewrite(source) do
    case locate(source) do
      {:ok, line, start_col, end_col} ->
        # `)` first: it is never before `(`, so inserting it cannot shift the
        # column the `(` was measured at.
        source
        |> insert_at(line, end_col, ")")
        |> insert_at(line, start_col, "(")
        |> rewrite()

      :none ->
        source
    end
  end

  # Single source of truth for both callbacks: either there is a proven span to
  # wrap, or there is nothing to report.
  defp locate(source) do
    with {:error, {meta, message, _token}} <-
           Code.string_to_quoted(source, columns: true, emit_warnings: false),
         true <- is_list(meta),
         line when is_integer(line) <- Keyword.get(meta, :line),
         col when is_integer(col) <- Keyword.get(meta, :column),
         {:ok, chars} <- line_chars(source, line),
         {:ok, start_col, end_col} <- span(message_text(message), chars, col),
         true <- keyword_if?(slice(chars, start_col, end_col)) do
      {:ok, line, start_col, end_col}
    else
      _ -> :none
    end
  end

  # Some parser errors carry a `{prefix, suffix}` pair instead of a plain
  # binary; both have to survive the fragment test without raising.
  defp message_text(message) when is_binary(message), do: message
  defp message_text({prefix, suffix}), do: to_string(prefix) <> to_string(suffix)
  defp message_text(other), do: inspect(other)

  defp span(message, chars, col) do
    cond do
      String.contains?(message, @kwlist_fragment) -> span_to_comma(chars, col)
      String.contains?(message, @nested_fragment) -> span_to_do(chars, col)
      true -> :none
    end
  end

  # "unexpected expression after keyword list": the blamed column holds the
  # comma that ended the `if`'s options, so the span ends right there. Its start
  # is the `if` that opens the nearest `<-` binding to the left.
  defp span_to_comma(chars, col) do
    with "," <- at(chars, col),
         arrow when is_integer(arrow) <- last_arrow_before(chars, col),
         start_col when is_integer(start_col) <- if_after(chars, arrow + 2),
         true <- start_col < col do
      {:ok, start_col, col}
    else
      _ -> :none
    end
  end

  # "…ambiguity in nested calls": the blamed column holds the `<-` of the last
  # binding, whose line ends with the block's own `do`. The span runs from the
  # `if` to just before that `do`.
  defp span_to_do(chars, col) do
    with "<" <- at(chars, col),
         "-" <- at(chars, col + 1),
         start_col when is_integer(start_col) <- if_after(chars, col + 2),
         end_col when is_integer(end_col) <- before_trailing_do(chars),
         true <- start_col < end_col do
      {:ok, start_col, end_col}
    else
      _ -> :none
    end
  end

  # Column of the `<` of the last `<-` that starts before `col`.
  defp last_arrow_before(chars, col) do
    1..(col - 2)//1
    |> Enum.filter(fn i -> at(chars, i) == "<" and at(chars, i + 1) == "-" end)
    |> List.last()
  end

  # Column of the `if` keyword that starts at or after `from`, with only blanks
  # in between. Anything else there means this is not a bare keyword `if`.
  defp if_after(chars, from) do
    index = skip_blanks(chars, from)

    if at(chars, index) == "i" and at(chars, index + 1) == "f" and
         at(chars, index + 2) in [" ", "\t", "("] do
      index
    end
  end

  defp skip_blanks(chars, index) do
    if at(chars, index) in [" ", "\t"], do: skip_blanks(chars, index + 1), else: index
  end

  # Column just past the end of the expression on a line that ends with the
  # block's ` do` — i.e. where the closing paren belongs. `nil` when the line
  # does not end that way (a trailing comment, `do:` keyword syntax, …), which
  # leaves the line untouched.
  defp before_trailing_do(chars) do
    last = trimmed_length(chars)

    if last > 3 and at(chars, last) == "o" and at(chars, last - 1) == "d" and
         at(chars, last - 2) in [" ", "\t"] do
      trimmed_length(chars, last - 3) + 1
    end
  end

  defp trimmed_length(chars, from \\ nil) do
    from = from || length(chars)

    if from > 0 and at(chars, from) in [" ", "\t", "\r"] do
      trimmed_length(chars, from - 1)
    else
      from
    end
  end

  # The span only counts if the parser reads it as a whole keyword-syntax `if`
  # — `do:` present, nothing beyond `do:`/`else:`. That is what keeps a wrongly
  # anchored `<-` (one inside a string, say) from ever being wrapped.
  defp keyword_if?(text) do
    case Code.string_to_quoted("(" <> text <> ")", emit_warnings: false) do
      {:ok, {:if, _meta, [_condition, options]}} -> keyword_options?(options)
      _ -> false
    end
  end

  defp keyword_options?(options) do
    Keyword.keyword?(options) and Keyword.has_key?(options, :do) and
      options |> Keyword.keys() |> Enum.all?(&(&1 in [:do, :else]))
  end

  # The parser counts columns in graphemes, not bytes and not codepoints (a
  # combining accent, a ZWJ emoji and a flag are each one column — checked in
  # the tests). Splitting the same way keeps every offset aligned.
  defp line_chars(source, line) do
    case source |> String.split("\n") |> Enum.at(line - 1) do
      nil -> :none
      text -> {:ok, String.graphemes(text)}
    end
  end

  defp at(_chars, index) when index < 1, do: nil
  defp at(chars, index), do: Enum.at(chars, index - 1)

  # Graphemes from `start_col` up to (not including) `end_col`, 1-indexed.
  defp slice(chars, start_col, end_col) do
    chars |> Enum.slice((start_col - 1)..(end_col - 2)//1) |> Enum.join()
  end

  # Insert `text` at the given 1-indexed line and 1-indexed column.
  defp insert_at(source, line, col, text) do
    lines = String.split(source, "\n")
    target = Enum.at(lines, line - 1) || ""
    {before, rest} = String.split_at(target, col - 1)

    lines
    |> List.replace_at(line - 1, before <> text <> rest)
    |> Enum.join("\n")
  end
end
