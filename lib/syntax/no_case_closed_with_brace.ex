defmodule Credence.Syntax.NoCaseClosedWithBrace do
  @moduledoc """
  Repairs a `do` block that is closed with `}` instead of `end`.

  LLM-generated code repeatedly closes `case`/`fn`/`if` blocks with `}` instead
  of `end`, producing `MismatchedDelimiterError` parse failures:

      case x do
        nil -> :default
        v -> v
      }          # <-- should be `end`

  Detection is parser-driven — `Code.string_to_quoted/2` reports the exact line
  and column of the mismatched `}` — so the rule fires only on a genuine
  `do … }` mismatch.

  ## Bad (won't parse — MismatchedDelimiterError)

      Map.put(state, :result, case Map.get(state, :val) do
        nil -> state
        v -> %{state | data: v}
      })

  ## Good

      Map.put(state, :result, case Map.get(state, :val) do
        nil -> state
        v -> %{state | data: v}
      end)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case detect(source) do
      {:ok, line, _column} ->
        [
          %Issue{
            rule: :no_case_closed_with_brace,
            message:
              "`do` block closed with `}` instead of `end` — replace mismatched `}` with `end`.",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source), do: fix_all(source)

  defp fix_all(source) do
    case detect(source) do
      {:ok, line, column} ->
        fixed = replace_brace_with_end(source, line, column)

        if fixed == source, do: source, else: fix_all(fixed)

      :none ->
        source
    end
  end

  # Returns the closing delimiter's position when the source fails to parse
  # specifically because a `do` block was closed by `}` instead of `end`.
  defp detect(source) do
    close_brace = String.to_atom("}")

    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == :do and
             Keyword.get(meta, :expected_delimiter) == :end and
             Keyword.get(meta, :closing_delimiter) == close_brace do
          {:ok, Keyword.get(meta, :end_line), Keyword.get(meta, :end_column)}
        else
          :none
        end

      _ ->
        :none
    end
  end

  defp replace_brace_with_end(source, line_no, col) do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        source

      line ->
        # Parser columns count codepoints and are 1-indexed.
        {before, rest} = line |> String.codepoints() |> Enum.split(col - 1)
        before = Enum.join(before)
        rest = Enum.join(rest)

        case rest do
          "}" <> after_brace ->
            # Ensure a space before `end` when `}` immediately follows a token
            # (e.g. `42}` → `42 end`, not `42end`).
            separator = if String.ends_with?(before, " ") or before == "", do: "", else: " "
            new_line = before <> separator <> "end" <> after_brace
            lines |> List.replace_at(line_no - 1, new_line) |> Enum.join("\n")

          _ ->
            source
        end
    end
  end
end
