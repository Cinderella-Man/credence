defmodule Credence.Syntax.NoExtraBracketAfterEnd do
  @moduledoc """
  Repairs a stray `]` placed immediately after a block-closing `end`.

  LLM-generated code occasionally produces `end]` (a closing bracket glued to
  `end`) inside nested blocks, causing a `MismatchedDelimiterError` that no
  existing rule can fix — the parser sees `]` as the block closer when it
  expected `end`.

  Detection is parser-driven: `Code.string_to_quoted/2` reports the exact line
  and column of the mismatched `]`, so the rule fires only on a genuine
  `do … ]` mismatch where `end` precedes the `]`.

  ## Bad (won't parse — MismatchedDelimiterError)

      case :ok do
        :ok -> 1
      end]

  ## Good

      case :ok do
        :ok -> 1
      end

  ## Why deleting the `]` is the only repair offered

  For the parser to report this error, the innermost open delimiter at the `]`
  is a `do` — so any `[` that is still open sits *below* that `do` on the
  delimiter stack and cannot legally be closed here. Once the `]` is dropped,
  the rule re-parses: it keeps the edit **only if the whole source now parses**.
  A source that still fails to parse without the `]` is one where the bracket
  was not the (only) mistake — e.g. an `end` is missing too — and guessing which
  token to invent there is not something this rule does. Such sources are left
  untouched *and* unflagged, so `analyze/1` and `fix/1` never disagree.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case repair(source) do
      {:ok, line, _fixed} ->
        [
          %Issue{
            rule: :no_extra_bracket_after_end,
            message: "Stray `]` after block-closing `end` — remove the extraneous bracket.",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case repair(source) do
      {:ok, _line, fixed} -> fixed
      :none -> source
    end
  end

  # The single decision both `analyze/1` and `fix/1` are built on: either there
  # is a stray `]` whose removal makes the source parse — `{:ok, line, fixed}` —
  # or there is nothing this rule may safely touch.
  defp repair(source) do
    with {:ok, line, col} <- locate_stray_bracket(source),
         true <- end_before_bracket?(source, line, col),
         {:ok, fixed} <- remove_bracket(source, line, col),
         true <- parses?(fixed) do
      {:ok, line, fixed}
    else
      _ -> :none
    end
  end

  defp parses?(source), do: match?({:ok, _}, Code.string_to_quoted(source))

  # Returns `{:ok, line, column}` when the source fails to parse specifically
  # because a `do` block was closed by `]` instead of `end`.
  defp locate_stray_bracket(source) do
    close_bracket = String.to_atom("]")

    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == :do and
             Keyword.get(meta, :expected_delimiter) == :end and
             Keyword.get(meta, :closing_delimiter) == close_bracket do
          {:ok, Keyword.get(meta, :end_line), Keyword.get(meta, :end_column)}
        else
          :none
        end

      _ ->
        :none
    end
  end

  # Verify that the `]` at (line_no, col) is immediately preceded by `end`.
  # The parser counts columns in graphemes, which is exactly what
  # `String.split_at/2` slices by — so combining accents, flags and ZWJ emoji
  # earlier on the line do not shift the cut.
  defp end_before_bracket?(source, line_no, col) do
    case line_at(source, line_no) do
      nil ->
        false

      line ->
        {before, rest} = String.split_at(line, col - 1)
        # The `]` must be present and the text before it must end with `end`.
        String.starts_with?(rest, "]") and String.ends_with?(String.trim_trailing(before), "end")
    end
  end

  # Remove the stray `]` at the exact position reported by the parser.
  defp remove_bracket(source, line_no, col) do
    lines = String.split(source, "\n")

    with line when is_binary(line) <- Enum.at(lines, line_no - 1),
         {before, "]" <> after_bracket} <- String.split_at(line, col - 1) do
      new_line = before <> after_bracket
      {:ok, lines |> List.replace_at(line_no - 1, new_line) |> Enum.join("\n")}
    else
      _ -> :none
    end
  end

  defp line_at(source, line_no), do: source |> String.split("\n") |> Enum.at(line_no - 1)
end
