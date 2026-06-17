defmodule Credence.Syntax.FixTruncatedBinaryClose do
  @moduledoc """
  Fixes truncated binary close delimiters caused by LLM output truncation.

  LLMs repeatedly truncate `<<...::binary>>` to `<<...::binary>)` inside
  nested delimiters (e.g. inside function calls or list constructors).
  This regex-based fix restores the missing `>` character.

  ## Bad (won't parse)

      result = <<first, char, rest::binary>
      [result | insert(char, <<first, rest::binary>)]

  ## Good

      result = <<first, char, rest::binary>>
      [result | insert(char, <<first, rest::binary>>)]
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  # Matches `::binary>)` where the closing `>>` was truncated to `>` then `)`
  # This captures `::binary` followed by one `>` and then `)` instead of `>>`
  @pattern ~r/::binary>\)/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@pattern, line) do
        [build_issue(line_no)]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &fix_line/1)
  end

  defp fix_line(line) do
    Regex.replace(@pattern, line, "::binary>>)")
  end

  defp build_issue(line_no) do
    %Issue{
      rule: :fix_truncated_binary_close,
      message: "Truncated binary close delimiter (`::binary>)`) should be `::binary>>)`.",
      meta: %{line: line_no}
    }
  end
end
