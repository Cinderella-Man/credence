defmodule Credence.Semantic.OutdentedHeredoc do
  @moduledoc """
  Fixes compiler warnings about outdented heredoc lines by re-indenting
  all body content to match the closing delimiter.

  LLMs often generate heredoc documentation where the body content is not
  indented to match the closing `\"\"\"`, causing a compiler warning that
  becomes a hard error under `--warnings-as-errors`.

  When any line in a heredoc is flagged, the fixer re-indents every
  outdented body line in that heredoc — not just the flagged one.

  ## Example

      # Warning: outdented heredoc line
      @doc \"\"\"
    Content not indented enough.
    More content.
      \"\"\"

      # Fixed:
      @doc \"\"\"
      Content not indented enough.
      More content.
      \"\"\"
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) do
    String.contains?(msg, "outdented heredoc line")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :outdented_heredoc,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{position: position}) do
    line_no = extract_line(position)

    if line_no do
      fix_heredoc(source, line_no - 1)
    else
      source
    end
  end

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  # Given a 0-based index of an outdented line, find the full heredoc
  # it belongs to and re-indent every body line.
  defp fix_heredoc(source, flagged_idx) do
    lines = String.split(source, "\n")

    with {:ok, opening_idx} <- find_opening(lines, flagged_idx),
         {:ok, closing_idx, closing_indent} <- find_closing(lines, flagged_idx) do
      lines
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {line, idx} ->
        if idx > opening_idx and idx < closing_idx do
          reindent_line(line, closing_indent)
        else
          line
        end
      end)
    else
      _ -> source
    end
  end

  defp reindent_line(line, target_indent) do
    if String.trim(line) == "" do
      line
    else
      current = leading_spaces(line)

      if current < target_indent do
        String.duplicate(" ", target_indent - current) <> line
      else
        line
      end
    end
  end

  # Scan backward to find the opening line containing """ or '''
  defp find_opening(lines, from_idx) do
    result =
      (from_idx - 1)..0//-1
      |> Enum.find(fn idx ->
        line = Enum.at(lines, idx)
        String.contains?(line, ~s(""")) or String.contains?(line, ~s('''))
      end)

    case result do
      nil -> :error
      idx -> {:ok, idx}
    end
  end

  # Scan forward to find the closing """ or ''' (must be alone on its line)
  defp find_closing(lines, from_idx) do
    result =
      (from_idx + 1)..(length(lines) - 1)//1
      |> Enum.find_value(fn idx ->
        line = Enum.at(lines, idx)
        trimmed = String.trim(line)

        if trimmed == ~s(""") or trimmed == ~s(''') do
          {idx, leading_spaces(line)}
        end
      end)

    case result do
      nil -> :error
      {idx, indent} -> {:ok, idx, indent}
    end
  end

  defp leading_spaces(line) do
    byte_size(line) - byte_size(String.trim_leading(line))
  end
end
