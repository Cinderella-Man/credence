defmodule Credence.Syntax.FixMismatchedClosingBrace do
  @moduledoc """
  Repairs a list bracket `]` that the LLM replaced with `}` before a `}` tuple/map closer.

  LLMs frequently replace `]` with `}` inside list expressions that precede `}`
  tuple/map closers, producing a `MismatchedDelimiterError` with
  `opening_delimiter: :"["`, `closing_delimiter: :"}"`, `expected_delimiter: :"]"`.

  The existing `CloseUnclosedBrace` only inserts missing `}` — it cannot swap
  bracket kind.  This rule parses the error position, locates the misapplied `}`,
  and swaps it to `]`.

  ## Bad (won't parse — MismatchedDelimiterError)

      {ok, [%{reason: x} | stats[:failures] || []}, stats}
                                                  ^ should be ]

  ## Good

      {ok, [%{reason: x} | stats[:failures] || []], stats}
                                                  ^
  """
  use Credence.Syntax.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  @impl true
  def analyze(source) do
    case detect(source) do
      {:ok, meta} ->
        [
          %Issue{
            rule: :fix_mismatched_closing_brace,
            message: "Mismatched `}` closing a `[` — replace the `}` with `]`.",
            meta: %{line: meta[:end_line]}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source), do: do_fix(source)

  defp do_fix(source) do
    case detect(source) do
      {:ok, meta} ->
        fixed = replace_brace_with_bracket(source, meta[:end_line], meta[:end_column])
        if fixed == source, do: source, else: do_fix(fixed)

      :none ->
        source
    end
  end

  # Returns the parser metadata when the source fails to parse specifically because
  # a `[` was closed by `}` instead of `]`.
  defp detect(source) do
    close_brace = String.to_atom("}")
    open_bracket = String.to_atom("[")
    close_bracket = String.to_atom("]")

    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == open_bracket and
             Keyword.get(meta, :expected_delimiter) == close_bracket and
             Keyword.get(meta, :closing_delimiter) == close_brace and
             nested_in_braces?(source, meta) do
          {:ok, meta}
        else
          :none
        end

      _ ->
        :none
    end
  end

  # The diagnostic alone is ambiguous: the opening `[` may itself be the typo.
  # This rule is only safe in its documented case, where a later code-level `}`
  # still closes the surrounding tuple or map.
  defp nested_in_braces?(source, meta) do
    with {:ok, offset} <-
           SourceMask.byte_offset(source, meta[:end_line], meta[:end_column]),
         shadow = SourceMask.mask(source),
         suffix_size = byte_size(shadow) - offset - 1,
         true <- suffix_size >= 0 do
      String.contains?(binary_part(shadow, offset + 1, suffix_size), "}")
    else
      _ -> false
    end
  end

  defp replace_brace_with_bracket(source, line_no, col) do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        source

      line ->
        # col is 1-indexed; split at the character before the `}`.
        {before, rest} = String.split_at(line, col - 1)

        case rest do
          "}" <> after_brace ->
            new_line = before <> "]" <> after_brace
            lines |> List.replace_at(line_no - 1, new_line) |> Enum.join("\n")

          _ ->
            source
        end
    end
  end
end
