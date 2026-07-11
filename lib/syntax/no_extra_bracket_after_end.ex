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
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case detect(source) do
      {:ok, line} ->
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
    case detect(source) do
      {:ok, _line} ->
        fixed = do_fix(source)

        if fixed != source and parses?(fixed) do
          fixed
        else
          source
        end

      :none ->
        source
    end
  end

  defp parses?(source), do: match?({:ok, _}, Code.string_to_quoted(source))

  # Returns `{:ok, end_line}` when the source fails to parse specifically because
  # a `do` block was closed by `]` instead of `end`, AND the `]` follows `end`.
  defp detect(source) do
    close_bracket = String.to_atom("]")

    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == :do and
             Keyword.get(meta, :expected_delimiter) == :end and
             Keyword.get(meta, :closing_delimiter) == close_bracket do
          line_no = Keyword.get(meta, :end_line)
          col = Keyword.get(meta, :end_column)

          if end_before_bracket?(source, line_no, col) do
            {:ok, line_no}
          else
            :none
          end
        else
          :none
        end

      _ ->
        :none
    end
  end

  # Verify that the `]` at (line_no, col) is immediately preceded by `end`.
  defp end_before_bracket?(source, line_no, col) do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        false

      line ->
        {before, rest} = String.split_at(line, col - 1)
        # The `]` must be present and the text before it must end with `end`.
        String.starts_with?(rest, "]") and String.ends_with?(String.trim_trailing(before), "end")
    end
  end

  # Remove the stray `]` at the exact position reported by the parser.
  defp do_fix(source) do
    close_bracket = String.to_atom("]")

    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == :do and
             Keyword.get(meta, :expected_delimiter) == :end and
             Keyword.get(meta, :closing_delimiter) == close_bracket do
          line_no = Keyword.get(meta, :end_line)
          col = Keyword.get(meta, :end_column)
          remove_bracket(source, line_no, col)
        else
          source
        end

      _ ->
        source
    end
  end

  defp remove_bracket(source, line_no, col) do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        source

      line ->
        {before, rest} = String.split_at(line, col - 1)

        case rest do
          "]" <> after_bracket ->
            new_line = before <> after_bracket
            lines |> List.replace_at(line_no - 1, new_line) |> Enum.join("\n")

          _ ->
            source
        end
    end
  end
end
