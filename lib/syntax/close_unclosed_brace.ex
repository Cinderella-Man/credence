defmodule Credence.Syntax.CloseUnclosedBrace do
  @moduledoc """
  Repairs unclosed `{` delimiters (tuple/map literals) that the LLM left
  dangling before an `end` keyword.

  LLMs frequently emit a tuple or map expression and forget the closing `}`,
  so the parser encounters `end` where it expected `}` and reports a
  `mismatched_delimiter` error with `opening_delimiter: :{`, `expected_delimiter: :}`,
  `closing_delimiter: :end`.

  The fix inserts the missing `}` at the end of the line that opened the `{`,
  then re-parses and repeats until the source parses or no more unclosed braces
  are found.

  ## Bad (won't parse — mismatched delimiter)

      def init(_opts) do
        {:ok, %{key: "value"}
      end

  ## Good

      def init(_opts) do
        {:ok, %{key: "value"}}
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Backstop on the fix loop.
  @max_fixes 50

  @impl true
  def analyze(source) do
    case detect(source) do
      {:ok, line} ->
        [
          %Issue{
            rule: :close_unclosed_brace,
            message:
              "Unclosed `{` delimiter — a tuple or map literal is missing its closing `}` before `end`.",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source), do: do_fix(source, 0)

  defp do_fix(source, count) when count < @max_fixes do
    case detect(source) do
      {:ok, line_no} ->
        fixed = insert_closing_brace(source, line_no)
        if fixed == source, do: source, else: do_fix(fixed, count + 1)

      :none ->
        source
    end
  end

  defp do_fix(source, _count), do: source

  # Returns `{:ok, line}` when the source fails to parse specifically because
  # a `{` was closed by `end` instead of `}`.
  # We use String.to_atom to build the brace atoms because writing `:"{"` or
  # `:"}"` inline causes the Elixir parser to misparse surrounding delimiters.
  defp detect(source) do
    open_brace = String.to_atom("{")
    close_brace = String.to_atom("}")

    case Code.string_to_quoted(source, columns: true) do
      {:error, {meta, _message, _token}} when is_list(meta) ->
        if Keyword.get(meta, :error_type) == :mismatched_delimiter and
             Keyword.get(meta, :opening_delimiter) == open_brace and
             Keyword.get(meta, :expected_delimiter) == close_brace and
             Keyword.get(meta, :closing_delimiter) == :end do
          {:ok, Keyword.get(meta, :line)}
        else
          :none
        end

      _ ->
        :none
    end
  end

  # Insert a `}` at the end of the line that contains the unclosed `{`.
  defp insert_closing_brace(source, line_no) do
    lines = String.split(source, "\n")

    case Enum.at(lines, line_no - 1) do
      nil ->
        source

      line ->
        lines
        |> List.replace_at(line_no - 1, line <> "}")
        |> Enum.join("\n")
    end
  end
end
