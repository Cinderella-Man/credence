defmodule Credence.Syntax.NoSpecDoBlock do
  @moduledoc """
  Detects and fixes `@spec do ... end` blocks where the LLM confused
  `@spec` with a block opener like a decorator.

  LLMs sometimes emit `@spec do` followed by a function definition and
  an extra `end`, as if `@spec` were a block statement. This is invalid
  Elixir — `@spec` takes a type expression, not a `do` block.

  Two fix strategies depending on the content:

    * **Body block** — when the content is a function with a `do ... end`
      body, the rule strips the spurious `@spec do` line and its matching
      `end`, dedenting the content between them.

    * **Spec line** — when the content is a single `def name(...) :: type`
      line (no body), the rule produces `@spec name(...) :: type`,
      removing the `def` prefix and the `do ... end` wrapper.

  ## Bad (won't parse — body block)

      @spec do
        def my_sqrt(number) when number >= 0 do
          number
        end
      end

  ## Good

      def my_sqrt(number) when number >= 0 do
        number
      end

  ## Bad (won't parse — spec line)

      @spec do
        def find_majority_element(list) :: integer()
      end

  ## Good

      @spec find_majority_element(list) :: integer()
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
    all_blocks =
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

    # Separate spec-like blocks (single def ... :: ... line) from body blocks
    {spec_blocks, body_blocks} =
      Enum.split_with(all_blocks, fn {s, e, _} ->
        spec_like_content?(lines, s, e)
      end)

    # Body blocks: remove @spec do / end, dedent content between
    body_remove = MapSet.new(Enum.flat_map(body_blocks, fn {s, e, _} -> [s, e] end))

    body_dedent =
      Enum.map(body_blocks, fn {s, e, indent} ->
        {s + 1, e - 1, indent}
      end)

    # Spec blocks: replace @spec do with @spec ..., remove content + end
    spec_remove = MapSet.new(Enum.flat_map(spec_blocks, fn {s, e, _} -> Enum.to_list(s..e) end))

    spec_replace =
      Map.new(
        Enum.map(spec_blocks, fn {s, e, indent} ->
          content = extract_spec_content(lines, s, e)
          new_line = String.duplicate(" ", indent) <> "@spec " <> content
          {s, new_line}
        end)
      )

    # Combined remove set
    remove_set = MapSet.union(body_remove, spec_remove)

    # Process lines: remove/replaced @spec do blocks, dedent body content
    lines
    |> Enum.with_index(0)
    |> Enum.flat_map(fn {line, idx} ->
      cond do
        MapSet.member?(remove_set, idx) and Map.has_key?(spec_replace, idx) ->
          [Map.fetch!(spec_replace, idx)]

        MapSet.member?(remove_set, idx) ->
          []

        true ->
          dedent =
            Enum.find_value(body_dedent, 0, fn {lo, hi, ind} ->
              if idx >= lo and idx <= hi, do: ind, else: nil
            end)

          if dedent > 0, do: [dedent_line(line, dedent)], else: [line]
      end
    end)
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

  # True when the content between @spec do and its matching end is a single
  # `def name(...) :: type` line (no body). These need special handling:
  # strip `def ` and produce a valid `@spec` attribute.
  defp spec_like_content?(lines, start_idx, end_idx) do
    content_lines = Enum.slice(lines, (start_idx + 1)..(end_idx - 1))
    trimmed = content_lines |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    case trimmed do
      [single] ->
        Regex.match?(~r/^\s*def\s+.*::/, single) and not Regex.match?(~r/\bdo\b(?!:)/, single)

      _ ->
        false
    end
  end

  # Extract the spec content from a spec-like block: find the first non-blank
  # line between @spec do and end, strip the `def ` prefix.
  defp extract_spec_content(lines, start_idx, end_idx) do
    content_lines = Enum.slice(lines, (start_idx + 1)..(end_idx - 1))

    content_line =
      Enum.find_value(content_lines, fn line ->
        if String.trim(line) != "", do: String.trim(line)
      end)

    case content_line do
      nil -> ""
      line -> Regex.replace(~r/^def\s+/, line, "")
    end
  end
end
