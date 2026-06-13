defmodule Credence.Syntax.PreferSingleDocAttribute do
  @moduledoc """
  Detects and fixes orphaned `@doc """` lines that are immediately followed
  by another `@doc` attribute.

  LLMs repeatedly emit `@doc """` immediately followed by `@doc "..."`
  without closing the heredoc, causing a `TokenMissingError`. Removing the
  orphaned incomplete `@doc """` line is safe because the second `@doc`
  already carries the actual documentation value.

  ## Bad (won't parse — TokenMissingError)

      defmodule Solution do
        @doc """
        @doc "Returns the length of the longest contiguous subarray."
        def longest_equal_zero_one(list) do
          :ok
        end
      end

  ## Good

      defmodule Solution do
        @doc "Returns the length of the longest contiguous subarray."
        def longest_equal_zero_one(list) do
          :ok
        end
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @doc_heredoc_open ~r/^\s*@doc\s+"""\s*$/

  @impl true
  def analyze(source) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if orphaned_doc_heredoc?(line, line_no, lines) do
        [
          %Issue{
            rule: :prefer_single_doc_attribute,
            message:
              "Orphaned `@doc \"\"\"` heredoc opening followed by another @doc attribute.",
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
    source
    |> String.split("\n")
    |> remove_orphaned_doc_heredocs()
    |> Enum.join("\n")
  end

  defp orphaned_doc_heredoc?(line, line_no, lines) do
    if Regex.match?(@doc_heredoc_open, line) do
      # Check if the next non-blank line is also a @doc attribute
      next_doc_line? =
        lines
        |> Enum.drop(line_no)
        |> Enum.find_value(false, fn next_line ->
          cond do
            String.trim(next_line) == "" -> nil
            Regex.match?(~r/^\s*@doc\b/, next_line) -> true
            true -> false
          end
        end)

      next_doc_line?
    else
      false
    end
  end

  defp remove_orphaned_doc_heredocs(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reject(fn {line, idx} ->
      Regex.match?(@doc_heredoc_open, line) and followed_by_doc?(lines, idx)
    end)
    |> Enum.map(fn {line, _idx} -> line end)
  end

  defp followed_by_doc?(lines, idx) do
    lines
    |> Enum.drop(idx + 1)
    |> Enum.find_value(false, fn next_line ->
      cond do
        String.trim(next_line) == "" -> nil
        Regex.match?(~r/^\s*@doc\b/, next_line) -> true
        true -> false
      end
    end)
  end
end
