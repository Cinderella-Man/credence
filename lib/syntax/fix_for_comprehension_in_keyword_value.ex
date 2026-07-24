defmodule Credence.Syntax.FixForComprehensionInKeywordValue do
  @moduledoc """
  Repairs the common LLM syntax error where a bare `for` comprehension appears
  as a value inside a container (map, keyword list, tuple), where the parser
  cannot tell the container's commas from the comprehension's option commas.

  When an LLM writes `%{foo: for x <- xs, into: %{}, do: {x, x}}`, Elixir errors
  with "unexpected comma. Parentheses are required to solve ambiguity inside
  containers." The deterministic fix is the one the error message itself asks
  for — wrap the comprehension in parentheses:
  `%{foo: (for x <- xs, into: %{}, do: {x, x})}`.

  ## Bad (won't parse — "unexpected comma… ambiguity inside containers")

      %{foo: for x <- [1, 2, 3], into: %{}, do: {x, x}}

  ## Good

      %{foo: (for x <- [1, 2, 3], into: %{}, do: {x, x})}

  ## How the closing paren is placed

  The opening paren goes where the parser points — it reports the ambiguity at
  the column of the `for` keyword, and the rule only proceeds once it has
  confirmed that the word `for` really is sitting there.

  The closing paren is *not* guessed by counting brackets: a comma or a brace
  inside a string (`do: "a, b"`), a `?,` char literal or a later `do:` on the
  same line all defeat that. Instead every position where the comprehension
  could plausibly end — right after a non-blank character, with only blanks
  (newlines included) between it and the container's own `,`, `}`, `]`, `)` or
  the end of input — is offered to the parser, nearest first, and the first
  one that parses on its own as a
  `for` whose **last** option is `do:` wins. So the span that gets wrapped is
  always a complete comprehension, as judged by Elixir itself, never a
  hand-rolled approximation of one.

  ## What it refuses to touch

  `analyze/1` reports exactly what `fix/1` will rewrite; anything the rule
  cannot place a closing paren for is left unflagged rather than reported as a
  problem the fix declines to solve. That covers:

    * an ambiguity the parser blames on something other than a `for` keyword
      (`%{foo: if x, do: :a, else: :b}`, `%{foo: with {:ok, x} <- f(), do: x}`)
      — a sister rule's job, and wrapping from the wrong column would corrupt
      the line;
    * a comprehension whose `do:` option is further away than 40 lines, or
      that has no `do:` at all — there is nothing to close;
    * a candidate span that only parses with a trailing option after `do:`
      (`%{foo: for x <- xs, do: x, bar: [do: 1]}` — the `bar:` pair belongs to
      the map, not to the comprehension). Requiring `do:` last is what keeps
      the rule from swallowing the rest of the container.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "unexpected comma. Parentheses are required to solve ambiguity inside containers"

  # How far past the `for` keyword the closing paren may land. A comprehension
  # written as a container value is a one-liner or close to it; the cap keeps
  # the candidate scan bounded on a large broken file.
  @window_lines 40

  # One file can hold several of these. Each rewrite is re-detected from
  # scratch, so the cap is only a backstop against an unforeseen loop.
  @max_rewrites 50

  @blanks [" ", "\t", "\n", "\r"]

  @impl true
  def analyze(source) do
    case locate(source) do
      {:ok, line, _col, _end_line, _end_col} ->
        [
          %Issue{
            rule: :fix_for_comprehension_in_keyword_value,
            message:
              "Bare `for` comprehension used as a value inside a container — " <>
                "wrap it in parentheses to resolve the comma ambiguity.",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source), do: rewrite(source, @max_rewrites)

  defp rewrite(source, 0), do: source

  defp rewrite(source, budget) do
    case locate(source) do
      {:ok, line, col, end_line, end_col} ->
        # `)` first: it is never before `(`, so inserting it cannot shift the
        # column the `(` was measured at.
        source
        |> insert_at(end_line, end_col, ")")
        |> insert_at(line, col, "(")
        |> rewrite(budget - 1)

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
         :ok <- check_for_keyword(lines, line, col),
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

  # The same error covers `if`, `with`, `case`… used bare in a container. Only
  # act when the column the parser blamed really holds the `for` keyword.
  defp check_for_keyword(lines, line, col) do
    with {:ok, chars} <- line_chars(lines, line),
         ["f", "o", "r"] <- Enum.slice(chars, col - 1, 3),
         next when next in [" ", "\t"] <- at(chars, col + 3),
         false <- identifier_char?(at(chars, col - 1)) do
      :ok
    else
      _ -> :none
    end
  end

  # Offer the parser every plausible end of the comprehension, nearest first,
  # and take the first span it accepts as a complete `for … do:`.
  defp find_close(lines, line, col) do
    tail =
      lines
      |> Enum.drop(line - 1)
      |> Enum.take(@window_lines)
      |> trim_first_line(col)
      |> Enum.join("\n")

    scan(String.graphemes(tail), [], line, col)
  end

  defp trim_first_line([first | rest], col) do
    [first |> String.graphemes() |> Enum.drop(col - 1) |> Enum.join() | rest]
  end

  defp trim_first_line([], _col), do: []

  defp scan([], _taken, _line, _col), do: :none

  defp scan([grapheme | rest], taken, line, col) do
    taken = [grapheme | taken]
    {line, col} = advance(grapheme, line, col)

    if cut_here?(grapheme, rest) and comprehension?(taken) do
      {:ok, line, col}
    else
      scan(rest, taken, line, col)
    end
  end

  defp advance("\n", line, _col), do: {line + 1, 1}
  defp advance(_grapheme, line, col), do: {line, col + 1}

  # A comprehension used as a container value is followed by the container's
  # own comma or closing delimiter (or ends the input). Anything else — an
  # operator, another word, a comment — means the value has not ended yet.
  # That is what keeps `do: x + 1` from being cut after the `x`, and it looks
  # past newlines too, so a value continued by a leading `|>` on the next line
  # is not mistaken for a finished one either.
  defp cut_here?(grapheme, rest) do
    grapheme not in @blanks and
      case Enum.drop_while(rest, &(&1 in @blanks)) do
        [] -> true
        [next | _] -> next in [",", "}", "]", ")"]
      end
  end

  # `taken` is the span in reverse. It counts only if the parser reads it as a
  # whole comprehension whose last option is `do:` — a trailing `into:`/`bar:`
  # pair after the `do:` belongs to the container, not to the `for`.
  defp comprehension?(taken) do
    text = taken |> Enum.reverse() |> Enum.join()

    case Code.string_to_quoted("(" <> text <> ")", emit_warnings: false) do
      {:ok, {:for, _meta, args}} when is_list(args) -> do_last?(List.last(args))
      _ -> false
    end
  end

  defp do_last?(options) when is_list(options), do: match?({:do, _}, List.last(options))
  defp do_last?(_options), do: false

  # The parser counts columns in graphemes, not bytes and not codepoints: a
  # combining accent, a ZWJ emoji and a flag are each one column (checked in
  # the tests). Splitting the same way keeps the offsets aligned; were it ever
  # not, `check_for_keyword/3` would see the wrong character and the rule would
  # stay silent.
  defp line_chars(lines, line) do
    case Enum.at(lines, line - 1) do
      nil -> :none
      text -> {:ok, String.graphemes(text)}
    end
  end

  defp at(_chars, index) when index < 1, do: nil
  defp at(chars, index), do: Enum.at(chars, index - 1)

  defp identifier_char?(<<c>>) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_, do: true
  defp identifier_char?(_grapheme), do: false

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
