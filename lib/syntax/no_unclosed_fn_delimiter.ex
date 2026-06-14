defmodule Credence.Syntax.NoUnclosedFnDelimiter do
  @moduledoc """
  Repairs an `fn` clause that is closed with `)` instead of `end`.

  LLMs repeatedly write `fn args -> body)` — letting the enclosing call's `)`
  stand in for the `fn`'s `end`:

      list |> Enum.max_by(fn {_, second} -> second)

  Elixir reports a `MismatchedDelimiterError` (`fn` opened, `)` found where
  `end` was expected). It never parses, so this is a REPAIR: insert the missing
  `end` immediately before the offending `)`.

  Detection is driven by the parser itself — `Code.string_to_quoted/2` pinpoints
  the exact `{line, column}` of the mismatched `)` and reports the opened/expected
  delimiters — so the rule fires only on a genuine `fn … )` mismatch and never on
  a line that merely happens to contain `fn`, `->`, and a trailing `)`.

  ## Bad (won't parse — MismatchedDelimiterError)

      list |> Enum.max_by(fn {_, second} -> second)

  ## Good

      list |> Enum.max_by(fn {_, second} -> second end)
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Bound on the repair loop (one iteration per `fn … )` mismatch in the file).
  @max_passes 100

  @impl true
  def analyze(source) do
    case detect(source) do
      {:ok, line, _col} ->
        [
          %Issue{
            rule: :no_unclosed_fn_delimiter,
            message: "`fn` block closed with `)` instead of `end`; insert the missing `end`.",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source), do: do_fix(source, 0)

  defp do_fix(source, passes) when passes < @max_passes do
    case detect(source) do
      {:ok, line, col} ->
        case insert_end_before(source, line, col) do
          ^source -> source
          fixed -> do_fix(fixed, passes + 1)
        end

      :none ->
        source
    end
  end

  defp do_fix(source, _passes), do: source

  # Ask the parser where (if anywhere) an `fn` was closed by `)` instead of
  # `end`. Returns `{:ok, end_line, end_column}` for the offending `)`.
  defp detect(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == :fn and
             Keyword.get(meta, :expected_delimiter) == :end and
             Keyword.get(meta, :closing_delimiter) == :")" do
          {:ok, Keyword.get(meta, :end_line), Keyword.get(meta, :end_column)}
        else
          :none
        end

      _ ->
        :none
    end
  end

  defp insert_end_before(source, line_no, col)
       when is_integer(line_no) and is_integer(col) do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        source

      line ->
        # Only splice when the parser-reported column truly lands on a `)`.
        case String.split_at(line, col - 1) do
          {before, ")" <> _ = rest} ->
            new_line = before <> " end" <> rest
            lines |> List.replace_at(line_no - 1, new_line) |> Enum.join("\n")

          _ ->
            source
        end
    end
  end

  defp insert_end_before(source, _line, _col), do: source
end
