defmodule Credence.Syntax.NoKeywordInsideTupleBrace do
  @moduledoc """
  Repairs the common LLM syntax error where a keyword list is written directly
  inside tuple braces — `{key: value}` — which Elixir rejects while parsing.

  LLMs carry the Python/JS dict literal over into Elixir and emit
  `{step_name: name, compensation: compensation}`, and the parser answers with
  "unexpected keyword list inside tuple. Did you mean to write a map (using
  %{...}) or a list (using [...]) instead?".

  The repair is the first thing the error message itself asks for: prefix the
  brace with `%`, turning the illegal tuple into the map literal the same
  characters already spell — `%{step_name: name, compensation: compensation}`.
  Nothing is moved, deleted or re-indented; a single `%` is inserted.

  ## Bad (won't parse — "unexpected keyword list inside tuple")

      data = [{step_name: name, compensation: compensation}]

  ## Good

      data = [%{step_name: name, compensation: compensation}]

  ## Where the `%` goes

  Never at a brace found by scanning text. The parser reports this error at the
  exact line and column of the offending `{`, and that column is what the rule
  inserts at — so a `{key: value}` sitting inside a string, a heredoc, a comment
  or a `~r{...}` sigil can never be touched, because the parser never blames it.

  Before inserting, the rule confirms the repair really produces a map: starting
  at the blamed `{` it hands the parser every `}`-terminated span in a bounded
  window and keeps the shortest one that parses on its own as a map literal.
  That is what tells `{a: "}", b: 1}` (the first `}` is inside a string) from a
  brace that genuinely closes there, and it is why the rewritten construct is
  always well-formed rather than probably-well-formed.

  One file can hold several of these, and the parser only ever reveals the first;
  the fix re-parses after each insertion and repeats until the error is gone.

  ## What it refuses to touch

  `analyze/1` reports exactly what `fix/1` will rewrite — both run the same
  search — so nothing is flagged as a problem the fix then declines to solve:

    * a keyword brace the parser blames with a *different* error, e.g. a
      positional entry after the keyword list (`{a: 1, b}`, "unexpected
      expression after keyword list" — a sister rule's business) or a keyword
      list that only starts on the brace's second line (`{\\n  a: 1\\n}`,
      "syntax error before: eol"); `%{a: 1, b}` would not parse either, so
      inserting `%` there would swap one syntax error for another;
    * a construct whose closing `}` lies beyond the search window, or which does
      not parse as a map once prefixed — there is no repair to make;
    * any source whose *first* parse error is not this one. The rule waits for
      its own error rather than editing a file another rule still owns.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "unexpected keyword list inside tuple"

  # How far past the blamed `{` its closing `}` may sit. A dict-shaped literal is
  # a one-liner or close to it; the cap keeps the candidate scan bounded on a
  # large broken file.
  @window_lines 20

  # One file can hold several of these. Each rewrite is re-detected from scratch,
  # so the cap is only a backstop against an unforeseen loop.
  @max_rewrites 50

  @impl true
  def analyze(source) do
    case locate(source) do
      {:ok, line, _col} ->
        [
          %Issue{
            rule: :no_keyword_inside_tuple_brace,
            message:
              "Keyword list written inside tuple braces — `{key: value}` is not valid " <>
                "Elixir. Write it as a map: `%{key: value}`.",
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
      {:ok, line, col} ->
        source
        |> insert_at(line, col, "%")
        |> rewrite(budget - 1)

      :none ->
        source
    end
  end

  # Single source of truth for both callbacks: either there is a brace to prefix,
  # or there is nothing to report.
  defp locate(source) do
    with {:error, {meta, message, _token}} <-
           Code.string_to_quoted(source, columns: true, emit_warnings: false),
         true <- is_list(meta),
         line when is_integer(line) <- Keyword.get(meta, :line),
         col when is_integer(col) <- Keyword.get(meta, :column),
         true <- String.contains?(message_text(message), @error_fragment),
         lines = String.split(source, "\n"),
         :ok <- check_brace(lines, line, col),
         :ok <- check_map_literal(lines, line, col) do
      {:ok, line, col}
    else
      _ -> :none
    end
  end

  # Some parser errors carry a `{prefix, suffix}` pair instead of a plain binary;
  # both have to survive the fragment test without raising.
  defp message_text(message) when is_binary(message), do: message
  defp message_text({prefix, suffix}), do: to_string(prefix) <> to_string(suffix)
  defp message_text(other), do: inspect(other)

  # The blamed column must really hold a `{`, and one that is not already part of
  # a map (`%{`) or a struct (`%Foo{`, `%__MODULE__{`) — prefixing either of those
  # with a second `%` would corrupt the line. Neither can produce this error, so
  # this only guards against a future parser reporting it somewhere else.
  defp check_brace(lines, line, col) do
    with {:ok, chars} <- line_chars(lines, line),
         "{" <- at(chars, col),
         false <- struct_or_map_char?(at(chars, col - 1)) do
      :ok
    else
      _ -> :none
    end
  end

  defp struct_or_map_char?(<<c>>) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_,
    do: true

  defp struct_or_map_char?("."), do: true
  defp struct_or_map_char?("%"), do: true
  defp struct_or_map_char?(_grapheme), do: false

  # Offer the parser every `}`-terminated span that starts at the blamed brace and
  # keep the first one it reads as a whole map literal. First, not last: the
  # shortest complete map is the construct the error points at — a longer span
  # would swallow whatever container encloses it.
  defp check_map_literal(lines, line, col) do
    window =
      lines
      |> Enum.drop(line - 1)
      |> Enum.take(@window_lines)
      |> trim_first_line(col)
      |> Enum.join("\n")

    if scan(String.graphemes(window), []), do: :ok, else: :none
  end

  defp trim_first_line([first | rest], col) do
    [first |> String.graphemes() |> Enum.drop(col - 1) |> Enum.join() | rest]
  end

  defp trim_first_line([], _col), do: []

  defp scan([], _taken), do: false

  defp scan([grapheme | rest], taken) do
    taken = [grapheme | taken]

    if grapheme == "}" and map_literal?(taken) do
      true
    else
      scan(rest, taken)
    end
  end

  # `taken` is the span in reverse, still opening with the illegal `{`. It counts
  # only if the very repair the rule performs — one `%` in front — makes the
  # parser read it as a map.
  defp map_literal?(taken) do
    text = "%" <> (taken |> Enum.reverse() |> Enum.join())

    match?({:ok, {:%{}, _meta, _pairs}}, Code.string_to_quoted(text, emit_warnings: false))
  end

  # The parser counts columns in graphemes, not bytes and not codepoints: a
  # combining accent, a ZWJ emoji and a flag are each one column (checked in the
  # tests). `String.graphemes/1` and `String.split_at/2` split the same way, so
  # the offsets stay aligned; were they ever not, `check_brace/3` would see the
  # wrong character and the rule would stay silent.
  defp line_chars(lines, line) do
    case Enum.at(lines, line - 1) do
      nil -> :none
      text -> {:ok, String.graphemes(text)}
    end
  end

  defp at(_chars, index) when index < 1, do: nil
  defp at(chars, index), do: Enum.at(chars, index - 1)

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
