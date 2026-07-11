defmodule Credence.Syntax.FixIfInlineElseCaseBlock do
  @moduledoc """
  Repairs the LLM syntax error where an inline `if ..., do: ..., else:` has its
  `else:` value set to a `case` block that spans multiple lines.

  The Elixir parser consumes `else: case expr` as the keyword value, then
  misinterprets the `case` block's `do ... end` as the `if`'s own block —
  producing a broken AST where the `if` has three arguments instead of two, the
  `case` node is missing its body, and the arrow clauses are orphaned in the
  `if`'s third argument. The code "parses" but the AST is semantically wrong.

  Rewriting to the `if/do/else/end` block form lets the parser correctly
  associate the `case ... do ... end` with the `else` branch.

  ## Bad (parser produces broken AST)

      if weight > 0, do: true, else:
        case Map.get(node, :children) do
          nil -> false
          children -> true
        end

  ## Good

      if weight > 0 do
        true
      else
        case Map.get(node, :children) do
          nil -> false
          children -> true
        end
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Pattern: a line ending with `else:` (inline keyword form) whose else value
  # is a `case` expression whose body was stolen by the parser.
  @if_inline_else_re ~r/^(\s*)if\s+(.+),\s*do:\s*(.+),\s*else:\s*$/

  @impl true
  def analyze(source) do
    case find_pattern(source) do
      {:ok, line_no} ->
        [
          %Issue{
            rule: :fix_if_inline_else_case_block,
            message:
              "`if` with inline `else:` containing a `case` block — use block form instead",
            meta: %{line: line_no}
          }
        ]

      :not_found ->
        []
    end
  end

  @impl true
  def fix(source) do
    case find_pattern(source) do
      {:ok, _line_no} ->
        do_fix(source)

      :not_found ->
        source
    end
  end

  # --- detection ---------------------------------------------------------------

  defp find_pattern(source) do
    lines = String.split(source, "\n")
    find_in_lines(lines, 0)
  end

  defp find_in_lines([], _idx), do: :not_found

  defp find_in_lines([line | rest], idx) do
    if Regex.match?(@if_inline_else_re, line) do
      # Confirm the next non-blank line is a `case ... do`
      case next_non_blank(rest) do
        nil ->
          find_in_lines(rest, idx + 1)

        next_line ->
          if Regex.match?(~r/^\s+case\s+.+\s+do\s*$/, next_line) do
            {:ok, idx + 1}
          else
            find_in_lines(rest, idx + 1)
          end
      end
    else
      find_in_lines(rest, idx + 1)
    end
  end

  defp next_non_blank([]), do: nil
  defp next_non_blank([l | _]) when l != "", do: l
  defp next_non_blank([_ | rest]), do: next_non_blank(rest)

  # --- fix ---------------------------------------------------------------------

  defp do_fix(source) do
    lines = String.split(source, "\n")
    rewrite_lines(lines)
  end

  defp rewrite_lines(lines) do
    case find_if_else_line(lines, 0) do
      {:ok, if_idx} ->
        if_line = Enum.at(lines, if_idx)

        case Regex.run(@if_inline_else_re, if_line) do
          [_, indent, condition, do_value] ->
            # Find the `case ... do` line (next non-blank after if_line)
            case_idx = find_next_non_blank(lines, if_idx + 1)

            case case_idx do
              nil ->
                Enum.join(lines, "\n")

              _ ->
                case_indent = get_indent(Enum.at(lines, case_idx))
                case_end_idx = find_end_at_indent(lines, case_idx + 1, case_indent)

                if case_end_idx == nil do
                  Enum.join(lines, "\n")
                else
                  # The case block lines (keep original indentation)
                  case_block = Enum.slice(lines, case_idx..case_end_idx)

                  # Build the replacement
                  new_lines =
                    [
                      "#{indent}if #{String.trim(condition)} do",
                      "#{indent}  #{String.trim(do_value)}",
                      "#{indent}else"
                    ] ++ case_block ++ ["#{indent}end"]

                  before = Enum.take(lines, if_idx)
                  after_lines = Enum.drop(lines, case_end_idx + 1)
                  Enum.join(before ++ new_lines ++ after_lines, "\n")
                end
            end

          _ ->
            Enum.join(lines, "\n")
        end

      :not_found ->
        Enum.join(lines, "\n")
    end
  end

  defp find_if_else_line([], _idx), do: :not_found

  defp find_if_else_line([line | rest], idx) do
    if Regex.match?(@if_inline_else_re, line) do
      case next_non_blank(rest) do
        nil ->
          find_if_else_line(rest, idx + 1)

        next_line ->
          if Regex.match?(~r/^\s+case\s+.+\s+do\s*$/, next_line) do
            {:ok, idx}
          else
            find_if_else_line(rest, idx + 1)
          end
      end
    else
      find_if_else_line(rest, idx + 1)
    end
  end

  # Find the next non-blank line's index in the list
  defp find_next_non_blank(lines, idx) do
    cond do
      idx >= length(lines) -> nil
      String.trim(Enum.at(lines, idx)) == "" -> find_next_non_blank(lines, idx + 1)
      true -> idx
    end
  end

  # Find `end` at the given indentation, tracking nested do/end pairs.
  defp find_end_at_indent(lines, idx, target_indent) do
    do_find_end(lines, idx, target_indent, 0)
  end

  defp do_find_end(lines, idx, target_indent, depth) do
    cond do
      idx >= length(lines) ->
        nil

      true ->
        line = Enum.at(lines, idx)
        line_indent = get_indent(line)
        trimmed = String.trim(line)

        cond do
          # `end` at the target indent — if depth is 0, this closes our block
          line_indent == target_indent and trimmed == "end" ->
            if depth == 0, do: idx, else: do_find_end(lines, idx + 1, target_indent, depth - 1)

          # A new block opener at or below target indent increases nesting
          block_opener?(trimmed) and line_indent >= target_indent ->
            do_find_end(lines, idx + 1, target_indent, depth + 1)

          true ->
            do_find_end(lines, idx + 1, target_indent, depth)
        end
    end
  end

  defp block_opener?(trimmed) do
    Regex.match?(~r/^(case|if|cond|unless|with|receive|try|fn)\b/, trimmed) and
      Regex.match?(~r/\bdo\s*$/, trimmed)
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end
end
