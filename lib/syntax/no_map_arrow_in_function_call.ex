defmodule Credence.Syntax.NoMapArrowInFunctionCall do
  @moduledoc """
  Repairs the LLM syntax error where map arrow syntax (`=>`) is used to pass a
  key/value pair as a single `Map.put/3` argument — `Map.put(%{}, key => value)`.

  The `=>` arrow is only valid inside a `%{...}` map literal, never as a function
  argument, so the parser stops at it with `syntax error before: '=>'`. The
  repair is the arity the call already spells: replace that one arrow with a
  comma, giving `Map.put(%{}, key, value)`. Two characters become one; nothing is
  moved, deleted or re-indented.

  ## Bad (won't parse — syntax error before: '=>')

      Map.put(%{}, key => value)

  ## Good

      Map.put(%{}, key, value)

  ## Which arrow gets rewritten

  Only the one the parser blames. `Code.string_to_quoted/2` reports this error at
  the exact line and column of the offending `=>`, and that position — not a
  scan of the text — is what the rule edits. An arrow inside a string, a
  heredoc, a comment or a sigil can therefore never be touched, because the
  parser never blames it: it is not a token.

  That anchor alone is not enough, because the syntax phase runs every rule's
  `fix/1` over any source that fails to parse — including a file that fails for
  an unrelated reason and merely *contains* perfectly good arrows
  (`Map.merge(%{}, %{a => 1})`, `Enum.reduce(l, %{}, fn ... end)`). Those arrows
  are never the first parse error of such a file, so this rule leaves them alone.

  ## What it refuses to touch

  `analyze/1` reports exactly what `fix/1` rewrites — both run the same search —
  so nothing is flagged as a problem the fix then declines to solve. The rule
  stays silent unless all of these hold:

    * the source's *first* parse error is `syntax error before: '=>'`, and the
      blamed position really holds an `=>`;
    * that arrow is the second argument of a single-line `Map.put(%{}, …` call
      whose key expression holds no comma — `foo(%{}, a => b)` (unknown arity),
      `Map.put(acc, a => b)` (no empty map) and a call split across lines are all
      left for a future rule rather than guessed at;
    * replacing that arrow with a comma makes the **whole file** parse, and the
      call it produces is a genuine three-argument `Map.put(%{}, _, _)` at the
      blamed line and column. This is what rejects the shapes whose comma repair
      would silently invent a non-existent arity: `Map.put(%{}, a => 1, b => 2)`
      (would become `Map.put/5`) and `Map.put(%{}, k => v, extra)` (would become
      `Map.put/4`) are reported as no issue and left byte-identical.

  A file holding more than one of these is repaired only if the first repair
  makes the whole file parse; otherwise the rule declines rather than edit a
  file whose remaining errors it cannot account for.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @error_fragment "syntax error before"
  @arrow_token "'=>'"
  @call_prefix "Map.put("

  @impl true
  def analyze(source) do
    case locate(source) do
      {:ok, line, _repaired} ->
        [
          %Issue{
            rule: :no_map_arrow_in_function_call,
            message:
              "Map arrow `=>` used as a function argument — it is only valid inside a " <>
                "`%{...}` literal. Pass the pair as two arguments: `Map.put(%{}, key, value)`.",
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

  # Single source of truth for both callbacks: either there is an arrow to turn
  # into a comma — and the resulting file is known to parse — or there is nothing
  # to report.
  defp locate(source) do
    with {:error, {meta, message, @arrow_token}} <-
           Code.string_to_quoted(source, columns: true, emit_warnings: false),
         true <- is_list(meta),
         line when is_integer(line) <- Keyword.get(meta, :line),
         col when is_integer(col) <- Keyword.get(meta, :column),
         true <- String.contains?(message_text(message), @error_fragment),
         {:ok, chars} <- line_chars(source, line),
         true <- arrow_at?(chars, col),
         {:ok, call_col} <- map_put_call_column(chars, col),
         repaired = replace_arrow(source, line, col),
         {:ok, ast} <- Code.string_to_quoted(repaired, emit_warnings: false, columns: true),
         true <- map_put_three_args?(ast, line, call_col) do
      {:ok, line, repaired}
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
  defp line_chars(source, line) do
    case source |> String.split("\n") |> Enum.at(line - 1) do
      nil -> :none
      text -> {:ok, String.graphemes(text)}
    end
  end

  defp arrow_at?(chars, col) when col >= 1 do
    Enum.at(chars, col - 1) == "=" and Enum.at(chars, col) == ">"
  end

  defp arrow_at?(_chars, _col), do: false

  # The blamed arrow has to be the second argument of a `Map.put(%{}, …` call
  # opened on the same line, with a key expression that holds no comma of its own
  # (`Map.put(%{}, foo(a, b) => v)` is declined rather than mis-split). Returns
  # the 1-indexed column the call opens at, which `map_put_three_args?/3` then
  # confirms against the re-parsed tree — so a textual match that is not really a
  # call (inside a string, say) cannot survive.
  defp map_put_call_column(chars, col) do
    prefix = Enum.take(chars, col - 1)

    case last_call_start(prefix) do
      nil ->
        :none

      index ->
        segment = prefix |> Enum.drop(index) |> Enum.join()

        if Regex.match?(~r/^Map\.put\(\s*%\{\}\s*,[^,]*$/, segment) do
          {:ok, index + 1}
        else
          :none
        end
    end
  end

  defp last_call_start(prefix) do
    width = String.length(@call_prefix)

    prefix
    |> Enum.with_index()
    |> Enum.reduce(nil, fn {grapheme, index}, last ->
      if grapheme == "M" and prefix |> Enum.slice(index, width) |> Enum.join() == @call_prefix,
        do: index,
        else: last
    end)
  end

  # Swap the two-grapheme `=>` at the blamed position for a single comma, closing
  # up the space the arrow sat behind (`key => v` reads `key, v`, not `key , v`).
  # Only that line changes, so every other line's numbering survives the re-parse.
  defp replace_arrow(source, line, col) do
    lines = String.split(source, "\n")
    chars = lines |> Enum.at(line - 1) |> String.graphemes()

    repaired_line =
      String.trim_trailing(Enum.join(Enum.take(chars, col - 1))) <>
        "," <> Enum.join(Enum.drop(chars, col + 1))

    lines
    |> List.replace_at(line - 1, repaired_line)
    |> Enum.join("\n")
  end

  # The repaired call must be `Map.put/3` with an empty map literal first — at the
  # very line and column the rule edited. A `Map.put/4` or `Map.put/5` born of a
  # trailing argument or a second arrow parses just fine, and this is what turns
  # it down.
  defp map_put_three_args?(ast, line, call_col) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {{:., _, [{:__aliases__, meta, [:Map]}, :put]}, _, [{:%{}, _, []}, _key, _value]} = node,
        found? ->
          {node,
           found? or (Keyword.get(meta, :line) == line and Keyword.get(meta, :column) == call_col)}

        node, found? ->
          {node, found?}
      end)

    found?
  end
end
