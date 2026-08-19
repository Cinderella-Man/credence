defmodule Credence.Syntax.CloseUnclosedDocHeredoc do
  @moduledoc """
  Detects and fixes unclosed `@doc` heredocs where the LLM jumps
  straight into function code without ever closing the triple-quote block.

  LLMs frequently emit `@doc` followed by triple-quotes on their own
  line and then immediately write a `def` on the next non-blank line
  without a closing set of triple-quotes in between. This causes a
  `TokenMissingError` (missing terminator). The fix inserts a closing
  triple-quote line — indented to match the `@doc` line — immediately
  before the `def` line.

  ## Bad (won't parse — TokenMissingError)

      defmodule Solution do
        @doc \"\"\"
        def find_min_max(list) do
          Enum.min_max(list)
        end
      end

  ## Good

      defmodule Solution do
        @doc \"\"\"
        \"\"\"
        def find_min_max(list) do
          Enum.min_max(list)
        end
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @doc_heredoc_open ~r/^(\s*)@doc\s+"""\s*$/

  # A line that opens a definition. The trailing `\b` is what keeps English prose
  # out: without it `defaults to 0 when absent.` — an ordinary first line of doc
  # text — counts as "the next def", and the rule then closes the heredoc above
  # it, emptying the doc and spilling its prose into the module body. Every
  # `def…` form Elixir defines is listed so that no real definition stops being
  # recognised; longer spellings come first so `defmacrop` is not read as
  # `defmacro` followed by a stray `p`.
  @def_line ~r/^\s*def(?:p|macrop|macro|guardp|guard|delegate|module|protocol|impl|struct|exception|overridable)?\b/

  @impl true
  def analyze(source) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if unclosed_doc_heredoc?(line, line_no, lines) do
        [
          %Issue{
            rule: :close_unclosed_doc_heredoc,
            message:
              "Unclosed `@doc \"\"\"` heredoc — the closing `\"\"\"` is missing before the next `def`.",
            meta: %{line: line_no}
          }
        ]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    lines = String.split(source, "\n")

    # Collect {insert_before_index, indent} for every unclosed @doc """
    insertions =
      lines
      |> Enum.with_index()
      |> Enum.flat_map(fn {line, idx} ->
        case Regex.run(@doc_heredoc_open, line) do
          [_, indent] ->
            remaining = Enum.drop(lines, idx + 1)

            if next_nonblank_is_def?(remaining) and not closed_before_def?(remaining) do
              offset = find_next_nonblank_offset(remaining)
              [{idx + 1 + offset, indent}]
            else
              []
            end

          _ ->
            []
        end
      end)

    # Apply insertions (sorted descending so indices stay valid)
    sorted = Enum.sort_by(insertions, &elem(&1, 0), :desc)

    Enum.reduce(sorted, lines, fn {insert_at, indent}, acc ->
      {before, after_} = Enum.split(acc, insert_at)
      before ++ [indent <> ~s(""")] ++ after_
    end)
    |> Enum.join("\n")
  end

  defp unclosed_doc_heredoc?(line, line_no, lines) do
    case Regex.run(@doc_heredoc_open, line) do
      [_, _indent] ->
        remaining = Enum.drop(lines, line_no)
        next_nonblank_is_def?(remaining) and not closed_before_def?(remaining)

      _ ->
        false
    end
  end

  defp next_nonblank_is_def?(lines) do
    Enum.find_value(lines, false, fn next_line ->
      cond do
        String.trim(next_line) == "" -> nil
        Regex.match?(@def_line, next_line) -> true
        true -> false
      end
    end)
  end

  defp closed_before_def?(lines) do
    Enum.find_value(lines, false, fn next_line ->
      cond do
        String.trim(next_line) == "" -> nil
        Regex.match?(~r/^\s*"""/, next_line) -> true
        Regex.match?(@def_line, next_line) -> false
        true -> false
      end
    end)
  end

  defp find_next_nonblank_offset(lines) do
    Enum.find_index(lines, fn line -> String.trim(line) != "" end) || length(lines)
  end
end
