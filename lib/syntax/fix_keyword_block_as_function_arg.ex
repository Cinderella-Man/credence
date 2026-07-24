defmodule Credence.Syntax.FixKeywordBlockAsFunctionArg do
  @moduledoc """
  Repairs the common LLM syntax error where a keyword-syntax `if`/`unless`
  appears as a non-first argument in a function call, causing parse ambiguity.

  When an LLM writes `f(arg, if cond, do: x, else: y)`, the Elixir parser
  cannot disambiguate the function-call commas from the keyword-syntax commas,
  and errors with "unexpected comma. Parentheses are required to solve ambiguity
  in nested calls."

  The fix is the one the parser itself asks for: wrap the keyword-syntax
  expression in parentheses. Nothing is moved, deleted or re-indented, so the
  repaired call passes exactly the expression that was written, in the same
  argument position, with the same `else`-clause behaviour.

  ## Bad (won't parse — "unexpected comma… ambiguity in nested calls")

      Enum.sort_by(list, & &1, if desc?, do: :desc, else: :asc)

  ## Good

      Enum.sort_by(list, & &1, (if desc?, do: :desc, else: :asc))

  ## Both anchors come from the parser, and the span is proved before it is used

  The opening paren goes at the error's own line/column — the parser points it
  straight at the start of the nested call it could not disambiguate. The rule
  refuses to go on unless the token sitting there is literally `if` or `unless`;
  the same error is raised by plenty of shapes that are not a keyword-syntax
  `if` at all (`f(a, b c, d)`, a `with` binding — a sister rule's job), and
  those are left untouched.

  The closing paren goes just before a closing bracket (`)`, `]` or `}`) later
  on the same line — but only after the text between the two anchors has been
  handed back to the parser and come back as a complete keyword-syntax
  `if`/`unless`: a condition plus options that are `do:` (required) and at most
  `else:`, and nothing else. The **longest** such span wins, so a bracket that
  merely lives inside the expression (`do: %{}`, `else: "y)z"`) cannot cut the
  span short.

  That proof is what makes the rewrite safe rather than plausible: the wrapped
  text parses on its own as exactly the `if` the author wrote, and the very next
  character closes the enclosing container, so the parenthesised expression is
  the whole argument and nothing but the argument.

  ## What it refuses to touch

    * a line where the error column is not an `if`/`unless` token — including
      when that column lands in the middle of an identifier;
    * a span with no closing bracket after it on the line, or whose text does
      not parse on its own as a `do:`-only/`do:`+`else:` `if`. That covers the
      `if` continued on the next line (`f(a,\\n  if c, do: 1,\\n  else: 2)`),
      whose one-line span `if c, do: 1` *does* parse but is followed by a comma,
      not a bracket — wrapping there would silently build a different, parseable
      program;
    * anything at all when the source already parses. `analyze/1` reports
      exactly the spans `fix/1` will wrap, and nothing else.

  Columns are counted in graphemes, the unit the Elixir tokenizer reports, so a
  combining accent or a multi-codepoint emoji earlier on the line does not shift
  either anchor.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "in nested calls"

  # One rewrite repairs one call; a file with more broken calls needs more
  # passes. The bound is a backstop — a pass that changes nothing stops the loop.
  @max_passes 20

  @closers [")", "]", "}"]

  @impl true
  def analyze(source) do
    case locate(source) do
      {:ok, loc} ->
        [
          %Issue{
            rule: :fix_keyword_block_as_function_arg,
            message: loc.message,
            meta: %{line: loc.line}
          }
        ]

      :error ->
        []
    end
  end

  @impl true
  def fix(source), do: fix_pass(source, @max_passes)

  defp fix_pass(source, 0), do: source

  defp fix_pass(source, passes_left) do
    case locate(source) do
      {:ok, loc} ->
        fixed = wrap(source, loc)
        if fixed == source, do: source, else: fix_pass(fixed, passes_left - 1)

      :error ->
        source
    end
  end

  # The single decision point: both `analyze/1` and `fix/1` go through here, so
  # nothing is ever flagged that would not also be rewritten.
  defp locate(source) do
    with {:error, {meta, msg, _token}} <- Sourceror.parse_string(source),
         true <- is_list(meta) and is_binary(msg),
         true <- String.contains?(msg, @error_fragment),
         line when is_integer(line) <- Keyword.get(meta, :line),
         col when is_integer(col) and col > 0 <- Keyword.get(meta, :column),
         graphemes when is_list(graphemes) <- line_graphemes(source, line),
         start_idx = col - 1,
         true <- keyword_start?(graphemes, start_idx),
         {:ok, close_idx} <- longest_if_span(graphemes, start_idx) do
      {:ok, %{line: line, start_idx: start_idx, close_idx: close_idx, message: msg}}
    else
      _ -> :error
    end
  end

  defp line_graphemes(source, line) do
    case source |> String.split("\n") |> Enum.at(line - 1) do
      nil -> :error
      text -> String.graphemes(text)
    end
  end

  # True when `if`/`unless` starts exactly at `idx` — a whole token, not the
  # tail of an identifier and not glued to one.
  defp keyword_start?(graphemes, idx) do
    Enum.any?(["if", "unless"], fn kw ->
      len = String.length(kw)

      graphemes |> Enum.slice(idx, len) |> Enum.join() == kw and
        not identifier_grapheme?(Enum.at(graphemes, idx + len)) and
        (idx == 0 or not identifier_grapheme?(Enum.at(graphemes, idx - 1)))
    end)
  end

  defp identifier_grapheme?(nil), do: false

  defp identifier_grapheme?(g) do
    g =~ ~r/^[A-Za-z0-9_?!]$/
  end

  # The longest span starting at `start_idx` that ends right before a closing
  # bracket and parses on its own as a complete keyword-syntax `if`/`unless`.
  # Returns the index of that bracket (where the closing paren goes).
  defp longest_if_span(graphemes, start_idx) do
    (start_idx + 1)..(length(graphemes) - 1)//1
    |> Enum.filter(&(Enum.at(graphemes, &1) in @closers))
    |> Enum.reverse()
    |> Enum.find(fn close_idx ->
      graphemes
      |> Enum.slice(start_idx, close_idx - start_idx)
      |> Enum.join()
      |> keyword_if?()
    end)
    |> case do
      nil -> :error
      close_idx -> {:ok, close_idx}
    end
  end

  # A complete `if`/`unless` written in keyword syntax: a condition plus `do:`
  # and at most `else:`. Anything else (a `do` block, a stray extra option, text
  # that does not parse at all) is not something this rule may wrap.
  defp keyword_if?(span) do
    case Code.string_to_quoted(span) do
      {:ok, {op, _meta, [_condition, opts]}} when op in [:if, :unless] ->
        Keyword.keyword?(opts) and Keyword.has_key?(opts, :do) and
          Enum.all?(opts, fn {key, _value} -> key in [:do, :else] end)

      _ ->
        false
    end
  end

  # Insert `)` first (higher column) so it does not shift the column of `(`.
  defp wrap(source, %{line: line, start_idx: start_idx, close_idx: close_idx}) do
    source
    |> insert_at(line, close_idx + 1, ")")
    |> insert_at(line, start_idx + 1, "(")
  end

  # Insert `text` at the given 1-indexed line and 1-indexed (grapheme) column.
  defp insert_at(source, line_no, col, text) do
    lines = String.split(source, "\n")
    target = Enum.at(lines, line_no - 1) || ""
    {before, after_} = String.split_at(target, col - 1)

    lines
    |> List.replace_at(line_no - 1, before <> text <> after_)
    |> Enum.join("\n")
  end
end
