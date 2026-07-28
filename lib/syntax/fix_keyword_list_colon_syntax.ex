defmodule Credence.Syntax.FixKeywordListColonSyntax do
  @moduledoc """
  Fixes the syntax error where LLMs write `:key: value` instead of `key: value`
  inside keyword lists (a Python/JS colon-on-wrong-side idiom).

  LLMs frequently emit `:read_concurrency: true` (atom prefix + keyword colon)
  instead of the correct `read_concurrency: true` (keyword syntax). The pattern
  `:identifier:` is never valid Elixir — the leading colon signals an atom, and
  the trailing colon attempts keyword syntax, producing a parse error.

  ## Bad (won't parse)

      :ets.new(table_name, [:set, :named_table, :public, :read_concurrency: true])

  ## Good

      :ets.new(table_name, [:set, :named_table, :public, read_concurrency: true])

  ## The safe core

  The source does not parse, so there is no AST. A blanket line-by-line regex
  over the whole file would rewrite the *same* `:identifier:` shape wherever it
  appears — including inside a string, a comment, or a heredoc of a file that is
  broken **elsewhere** — silently turning a valid literal into different text
  (and, once the real break is fixed, a different parseable program).

  Instead the rule keys off the parser's own error position. Elixir's parser
  reports the offending second colon precisely (`unexpected token: ":"`); the
  rule confirms the bytes ending there really are `:identifier:` and deletes
  only that leading colon. Text inside strings, comments and heredocs never
  produces this error at its interior, so it is never touched. Files with more
  than one such colon are repaired by re-parsing after each edit.
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # One edit removes one stray colon; a file with more needs more passes. The
  # cap is a belt-and-braces guard against a rewrite loop.
  @max_passes 50

  # A keyword-list identifier: lowercase/underscore start, optional `?`/`!` end.
  @identifier ~r/^[a-z_][a-zA-Z0-9_]*[?!]?$/

  @impl true
  def analyze(source), do: collect_issues(source, @max_passes, [])

  defp collect_issues(_source, 0, acc), do: Enum.reverse(acc)

  defp collect_issues(source, budget, acc) do
    case rewrite(source) do
      {:ok, line, identifier, fixed} when fixed != source ->
        collect_issues(fixed, budget - 1, [build_issue(line, identifier) | acc])

      _ ->
        Enum.reverse(acc)
    end
  end

  @impl true
  def fix(source), do: run(source, @max_passes)

  defp run(source, 0), do: source

  defp run(source, budget) do
    case rewrite(source) do
      {:ok, _line, _id, fixed} when fixed != source -> run(fixed, budget - 1)
      _ -> source
    end
  end

  # The single decision point shared by `analyze/1` and `fix/1`, so the check
  # never flags a case the fix would not touch.
  defp rewrite(source) do
    with {:error, {meta, msg, _token}} <- Code.string_to_quoted(source),
         true <- is_list(meta),
         true <- String.contains?(message_to_string(msg), "unexpected token"),
         line when is_integer(line) <- Keyword.get(meta, :line),
         col when is_integer(col) <- Keyword.get(meta, :column),
         {:ok, pos} <- line_col_to_pos(source, line, col),
         {:ok, identifier, first_colon} <- keyword_colon_at(source, pos) do
      fixed =
        binary_part(source, 0, first_colon) <>
          binary_part(source, first_colon + 1, byte_size(source) - first_colon - 1)

      {:ok, line, identifier, fixed}
    else
      _ -> :none
    end
  end

  # A parse error carries either a binary message or an `{opening, hint}` tuple
  # (e.g. "unexpected reserved word"); `to_string/1` raises on the tuple.
  defp message_to_string(msg) when is_binary(msg), do: msg

  defp message_to_string({opening, hint}) when is_binary(opening) and is_binary(hint),
    do: opening <> hint

  defp message_to_string(other), do: inspect(other)

  # `pos` is the byte offset of the character the parser flagged — the second
  # colon of `:identifier:`. Confirm the bytes ending there really form that
  # shape and return the identifier plus the byte offset of the *first* colon.
  defp keyword_colon_at(source, pos) do
    with true <- pos >= 0 and pos < byte_size(source),
         ?: <- :binary.at(source, pos),
         id_start = scan_identifier_back(source, pos - 1),
         true <- id_start < pos,
         identifier = binary_part(source, id_start, pos - id_start),
         true <- Regex.match?(@identifier, identifier),
         true <- id_start - 1 >= 0,
         ?: <- :binary.at(source, id_start - 1) do
      {:ok, identifier, id_start - 1}
    else
      _ -> :error
    end
  end

  # Walk backward over identifier bytes; return the index of the first one.
  defp scan_identifier_back(_source, i) when i < 0, do: 0

  defp scan_identifier_back(source, i) do
    if identifier_byte?(:binary.at(source, i)),
      do: scan_identifier_back(source, i - 1),
      else: i + 1
  end

  defp identifier_byte?(b) do
    (b >= ?a and b <= ?z) or (b >= ?A and b <= ?Z) or (b >= ?0 and b <= ?9) or
      b in [?_, ??, ?!]
  end

  # Convert 1-indexed line/column (the parser counts columns in codepoints) to a
  # 0-indexed *byte* position in the source.
  defp line_col_to_pos(source, line, col) do
    lines = String.split(source, "\n")

    with true <- line >= 1 and line <= length(lines),
         target = Enum.at(lines, line - 1),
         true <- col >= 1 and col - 1 <= String.length(target) do
      preceding =
        lines
        |> Enum.take(line - 1)
        |> Enum.reduce(0, fn l, acc -> acc + byte_size(l) + 1 end)

      {:ok, preceding + byte_size(String.slice(target, 0, col - 1))}
    else
      _ -> :error
    end
  end

  defp build_issue(line, identifier) do
    %Issue{
      rule: :fix_keyword_list_colon_syntax,
      message: "LLM colon-on-wrong-side keyword `:#{identifier}:` should be `#{identifier}:`.",
      meta: %{line: line}
    }
  end
end
