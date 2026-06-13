defmodule Credence.Syntax.NoSpecDoBlock do
  @moduledoc """
  Detects and fixes `@spec do ... end` blocks where the LLM confused
  `@spec` with a block opener like a decorator.

  LLMs sometimes emit `@spec do` followed by a function definition and
  an extra `end`, as if `@spec` were a block statement. This is invalid
  Elixir — `@spec` takes a type expression, not a `do` block.

  The rule strips the spurious `@spec do` line and its matching `end`,
  dedenting the content between them, leaving the function definition
  intact and compilable. No behavior change — specs are metadata, and
  the original never compiled.

  ## Bad (won't parse)

      @spec do
        def my_sqrt(number) when number >= 0 do
          number
        end
      end

  ## Good

      def my_sqrt(number) when number >= 0 do
        number
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @spec_do_pattern ~r/^\s*@spec\s+do\s*$/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@spec_do_pattern, line) do
        [
          %Issue{
            rule: :no_spec_do_block,
            message: "`@spec do` is invalid — `@spec` takes a type expression, not a `do` block.",
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

    # Find all @spec do lines and their matching end lines
    removals =
      lines
      |> Enum.with_index(0)
      |> Enum.flat_map(fn {line, idx} ->
        if Regex.match?(@spec_do_pattern, line) do
          case find_matching_end(lines, idx) do
            nil -> []
            end_idx -> [{idx, end_idx, line_indent(line)}]
          end
        else
          []
        end
      end)

    # Build sets of indices to remove and ranges to dedent
    remove_set = MapSet.new(Enum.flat_map(removals, fn {s, e, _} -> [s, e] end))

    dedent_ranges =
      Enum.map(removals, fn {s, e, indent} ->
        {s + 1, e - 1, indent}
      end)

    # Process lines: remove @spec do / end, dedent content between
    lines
    |> Enum.with_index(0)
    |> Enum.map(fn {line, idx} ->
      if MapSet.member?(remove_set, idx) do
        nil
      else
        dedent =
          Enum.find_value(dedent_ranges, 0, fn {lo, hi, ind} ->
            if idx >= lo and idx <= hi, do: ind, else: nil
          end)

        if dedent > 0, do: dedent_line(line, dedent), else: line
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  # Walk forward from the @spec do line, tracking do/end depth.
  # Returns the index of the matching `end`, or nil if not found.
  defp find_matching_end(lines, spec_do_idx) do
    total = length(lines)

    result =
      Enum.reduce_while((spec_do_idx + 1)..(total - 1), 1, fn idx, depth ->
        line = Enum.at(lines, idx)
        new_depth = depth + count_do_keyword(line) - count_end_keyword(line)

        if new_depth <= 0 do
          {:halt, {:found, idx}}
        else
          {:cont, new_depth}
        end
      end)

    case result do
      {:found, idx} -> idx
      _ -> nil
    end
  end

  # Count `do` block-openers on a line (excludes `do:` keyword syntax).
  defp count_do_keyword(line) do
    Regex.scan(~r/\bdo\b(?!:)/, line) |> length()
  end

  # Count `end` block-closers on a line.
  defp count_end_keyword(line) do
    Regex.scan(~r/\bend\b/, line) |> length()
  end

  defp line_indent(line) do
    case Regex.run(~r/^( *)/, line) do
      [_, spaces] -> String.length(spaces)
      _ -> 0
    end
  end

  defp dedent_line(line, indent) do
    if String.trim(line) == "" do
      line
    else
      prefix = String.duplicate(" ", indent)

      if String.starts_with?(line, prefix) do
        String.slice(line, indent..-1//1)
      else
        line
      end
    end
  end
end
