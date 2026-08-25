defmodule Credence.Syntax.NoKeywordIfBareInTuple do
  @moduledoc """
  Repairs the common LLM syntax error where a keyword-syntax `if`/`unless`
  (`do:`/`else:`) appears bare inside a container, where the parser cannot tell
  the container's commas from the `if`'s option commas.

  When an LLM writes `{:ok, if num < 1, do: 1, else: num}`, Elixir errors with
  "unexpected comma. Parentheses are required to solve ambiguity inside
  containers." The deterministic fix is the one the error message itself asks
  for — wrap the conditional in parentheses:
  `{:ok, (if num < 1, do: 1, else: num)}`.

  A tuple is where this shape shows up most (hence the name), but the parser
  raises the same error for a list, a map or a keyword value, and the repair is
  identical there, so those are covered too.

  ## Bad (won't parse — "unexpected comma… ambiguity inside containers")

      {:ok, if num < 1, do: 1, else: num}

  ## Good

      {:ok, (if num < 1, do: 1, else: num)}

  ## How the parentheses are placed

  The opening paren goes where the parser points — it reports the ambiguity at
  the column where the ambiguous call begins — and the rule only proceeds once
  it has confirmed that the word sitting there really is `if` or `unless`.

  The closing paren is *not* guessed by counting brackets: a comma or a brace
  inside a string (`else: "}"`), a `?,` char literal, or a later `do:` on the
  same line all defeat that. Instead every position where the conditional could
  plausibly end — right after a non-blank character, with only blanks (newlines
  included) between it and the container's own `,`, `}`, `]`, `)` — is handed to
  the parser, and the span is kept only if it parses on its own as an
  `if`/`unless` whose options are `do:` and `else:` and nothing else. The
  *longest* such span wins, because the shortest one always stops at `do:` and
  would leave the `else:` branch stranded outside the parentheses.

  So the span that gets wrapped is always a complete conditional as judged by
  Elixir itself, never a hand-rolled approximation of one — nothing is moved,
  deleted or re-indented, and no paren can ever land inside a string literal.

  ## What it refuses to touch

  `analyze/1` reports exactly what `fix/1` will rewrite; anything the rule
  cannot place a closing paren for is left unflagged rather than reported as a
  problem the fix declines to solve. That covers:

    * an ambiguity the parser blames on something other than an `if`/`unless`
      keyword (`{:ok, foo a, b: 1}`, a bare `for` in a container — a sister
      rule's job); wrapping from the wrong column would corrupt the line;
    * a conditional whose end lies beyond the search window, or that has no
      `do:` at all — there is nothing to close;
    * a candidate span that only parses with a foreign option after the `do:`
      or `else:` (`{:ok, if a, do: 1, else: 2, k: [do: 5]}` — the `k:` pair
      belongs to the tuple, not to the `if`). Requiring the options to be
      exactly `do:`/`else:` is what keeps the rule from swallowing the rest of
      the container.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "unexpected comma. Parentheses are required to solve ambiguity inside containers"

  # How far past the `if` keyword the closing paren may land. A conditional
  # written as a container value is a one-liner or close to it; the cap keeps
  # the candidate scan bounded on a large broken file.
  @window_lines 20

  @blanks [" ", "\t", "\n", "\r"]

  @conditionals ["if", "unless"]

  @impl true
  def analyze(source) do
    case locate(source) do
      {:ok, line, _col, _end_line, _end_col} ->
        [
          %Issue{
            rule: :no_keyword_if_bare_in_tuple,
            message:
              "Bare keyword-syntax `if`/`unless` used as a value inside a container — " <>
                "wrap it in parentheses to resolve the comma ambiguity.",
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
      {:ok, line, col, end_line, end_col} ->
        # `)` first: it is never before `(`, so inserting it cannot shift the
        # column the `(` was measured at.
        source
        |> insert_at(end_line, end_col, ")")
        |> insert_at(line, col, "(")
        |> rewrite()

      :none ->
        source
    end
  end

  # Single source of truth for both callbacks: either there is a span to wrap,
  # or there is nothing to report.
  defp locate(source) do
    with {:error, {meta, message, _token}} <-
           Code.string_to_quoted(source, columns: true, emit_warnings: false),
         true <- is_list(meta),
         line when is_integer(line) <- Keyword.get(meta, :line),
         col when is_integer(col) <- Keyword.get(meta, :column),
         true <- String.contains?(message_text(message), @error_fragment),
         lines = String.split(source, "\n"),
         :ok <- check_conditional_keyword(lines, line, col),
         {:ok, end_line, end_col} <- find_close(lines, line, col) do
      {:ok, line, col, end_line, end_col}
    else
      _ -> :none
    end
  end

  # Some parser errors carry a `{prefix, suffix}` pair instead of a plain
  # binary; both have to survive the fragment test without raising.
  defp message_text(message) when is_binary(message), do: message
  defp message_text({prefix, suffix}), do: to_string(prefix) <> to_string(suffix)
  defp message_text(other), do: inspect(other)

  # The same error covers `for`, `with`, a plain call… used bare in a container.
  # Only act when the column the parser blamed really holds `if` or `unless`.
  defp check_conditional_keyword(lines, line, col) do
    with {:ok, chars} <- line_chars(lines, line),
         word when word in @conditionals <- word_at(chars, col),
         next when next in [" ", "\t"] <- at(chars, col + String.length(word)),
         false <- boundary_char?(at(chars, col - 1)) do
      :ok
    else
      _ -> :none
    end
  end

  defp word_at(chars, col) do
    Enum.find(@conditionals, fn word ->
      Enum.slice(chars, col - 1, String.length(word)) == String.graphemes(word)
    end)
  end

  # Offer the parser every plausible end of the conditional and keep the last
  # span it accepts as a complete `if`/`unless`. Last, not first: the first one
  # always cuts at the `do:` value and would leave `else:` outside the parens.
  defp find_close(lines, line, col) do
    window = lines |> Enum.drop(line - 1) |> Enum.take(@window_lines)
    truncated? = length(lines) - (line - 1) > @window_lines
    tail = window |> trim_first_line(col) |> Enum.join("\n")

    scan(String.graphemes(tail), [], line, col, truncated?, :none)
  end

  defp trim_first_line([first | rest], col) do
    [first |> String.graphemes() |> Enum.drop(col - 1) |> Enum.join() | rest]
  end

  defp trim_first_line([], _col), do: []

  defp scan([], _taken, _line, _col, _truncated?, best), do: best

  defp scan([grapheme | rest], taken, line, col, truncated?, best) do
    taken = [grapheme | taken]
    {line, col} = advance(grapheme, line, col)

    best =
      if cut_here?(grapheme, rest, truncated?) and conditional?(taken),
        do: {:ok, line, col},
        else: best

    scan(rest, taken, line, col, truncated?, best)
  end

  defp advance("\n", line, _col), do: {line + 1, 1}
  defp advance(_grapheme, line, col), do: {line, col + 1}

  # A conditional used as a container value is followed by the container's own
  # comma or closing delimiter. Anything else — an operator, another word, a
  # comment — means the value has not ended yet. That is what keeps `else: x + 1`
  # from being cut after the `x`, and it looks past newlines too, so a value
  # continued by a leading `|>` on the next line is not mistaken for a finished
  # one either. Running out of text only counts as an end when the window really
  # reached the end of the file; on a truncated window it is just as likely to
  # be the middle of a token.
  #
  # A comma is only the container's if what follows it is not another branch of
  # the same conditional. Without that guard, a comment sitting between the
  # `do:` value and the `else:` (`{:ok, if a, do: 1, else: 2 # note`) blocks the
  # real end of the span, the `do:`-only prefix becomes the longest candidate,
  # and the repair would silently demote `else: 2` to a third tuple element
  # instead of the `if`'s else branch. Better to leave such a line unflagged.
  defp cut_here?(grapheme, rest, truncated?) do
    grapheme not in @blanks and
      case Enum.drop_while(rest, &(&1 in @blanks)) do
        [] -> not truncated?
        ["," | after_comma] -> not branch_follows?(after_comma)
        [next | _] -> next in ["}", "]", ")"]
      end
  end

  defp branch_follows?(chars) do
    text = chars |> Enum.drop_while(&(&1 in @blanks)) |> Enum.take(5) |> Enum.join()

    String.starts_with?(text, "do:") or String.starts_with?(text, "else:")
  end

  # `taken` is the span in reverse. It counts only if the parser reads it as a
  # whole keyword-syntax `if`/`unless` whose options are exactly `do:`/`else:` —
  # a trailing `k:` pair belongs to the container, not to the conditional.
  defp conditional?(taken) do
    text = taken |> Enum.reverse() |> Enum.join()

    case Code.string_to_quoted("(" <> text <> ")", emit_warnings: false) do
      {:ok, {head, _meta, args}} when head in [:if, :unless] and is_list(args) ->
        branches_only?(List.last(args))

      _ ->
        false
    end
  end

  defp branches_only?([_ | _] = options) do
    Enum.all?(options, fn
      {key, _value} -> key in [:do, :else]
      _other -> false
    end)
  end

  defp branches_only?(_options), do: false

  # The parser counts columns in graphemes, not bytes and not codepoints: a
  # combining accent, a ZWJ emoji and a flag are each one column (checked in
  # the tests). Splitting the same way keeps the offsets aligned; were it ever
  # not, `check_conditional_keyword/3` would see the wrong character and the
  # rule would stay silent.
  defp line_chars(lines, line) do
    case Enum.at(lines, line - 1) do
      nil -> :none
      text -> {:ok, String.graphemes(text)}
    end
  end

  defp at(_chars, index) when index < 1, do: nil
  defp at(chars, index), do: Enum.at(chars, index - 1)

  # What may not sit immediately before the keyword: another identifier
  # character (`elsif`), a dot (`Foo.if`) or a colon (the atom `:if`).
  defp boundary_char?(<<c>>) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_, do: true
  defp boundary_char?("."), do: true
  defp boundary_char?(":"), do: true
  defp boundary_char?(_grapheme), do: false

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
