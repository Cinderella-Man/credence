defmodule Credence.Semantic.FixRangeStep do
  @moduledoc """
  Fixes Elixir 1.19+ compiler warnings about implicit negative step in ranges.

  In Elixir 1.19+, ranges like `0..-2` default to step -1 but require the
  explicit `0..-2//-1` syntax. This rule matches the diagnostic message
  and rewrites the ambiguous range with the explicit step form.

  ## Example

      # Warning: 0..-2 has a default step of -1, please write 0..-2//-1 instead
      String.slice(word, 0..-2)

      # Fixed:
      String.slice(word, 0..-2//-1)
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) do
    String.contains?(msg, "has a default step of -1, please write")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :fix_range_step,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    line_no = extract_line(position)

    if line_no do
      # Extract the old and new range expressions from the diagnostic message.
      # Message format: "0..-2 has a default step of -1, please write 0..-2//-1 instead"
      case parse_message(msg) do
        {:ok, old_range, new_range} ->
          fix_line(source, line_no, old_range, new_range)

        :error ->
          source
      end
    else
      source
    end
  end

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp parse_message(msg) do
    case Regex.run(~r/^(\S+) has a default step of -1, please write (\S+) instead$/, msg) do
      [_, old_range, new_range] -> {:ok, old_range, new_range}
      _ -> :error
    end
  end

  defp fix_line(source, line_no, old_range, new_range) do
    lines = String.split(source, "\n")
    idx = line_no - 1

    if idx >= 0 and idx < length(lines) do
      target = Enum.at(lines, idx)
      # Only replace if the old_range appears on this line and doesn't already
      # have an explicit step (contain //).
      if String.contains?(target, old_range) and not String.contains?(target, "#{old_range}//") do
        updated = String.replace(target, old_range, new_range)
        List.replace_at(lines, idx, updated) |> Enum.join("\n")
      else
        source
      end
    else
      source
    end
  end
end
