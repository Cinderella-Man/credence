defmodule Credence.Syntax.FixAfterClausePatternArrow do
  @moduledoc """
  Detects and fixes `after` clauses inside `try` blocks that incorrectly use
  pattern matching with `->`.

  LLMs (Python/JS finally-ism) frequently emit `after {pattern} -> body` inside
  `try` blocks, but `after` is not a clause-based construct — it is a plain
  block of expressions. The `->` is a misplaced-operator compile error.

  The deterministic fix removes the pattern line (containing `->`) and de-indents
  the body to the pattern's indentation level.

  ## Bad (won't compile — misplaced operator ->)

      try do
        {:ok, :value}
      after
        {result, new_state} ->
          IO.puts("after block")
          {result, new_state}
      end

  ## Good

      try do
        {:ok, :value}
      after
        IO.puts("after block")
        {result, new_state}
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case find_after_pattern_arrow(source) do
      {:ok, line} ->
        [
          %Issue{
            rule: :fix_after_clause_pattern_arrow,
            message: "`after` clause uses pattern matching with `->` — remove the pattern",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case find_after_pattern_arrow(source) do
      {:ok, _line} ->
        fixed = remove_pattern_arrow(source)
        if fixed != source, do: fix(fixed), else: source

      :none ->
        source
    end
  end

  # Parse with Sourceror and look for a `try` block whose `after` clause
  # contains `->` arrows. Returns `{:ok, line}` where line is the line of the
  # `->` arrow, or `:none`.
  defp find_after_pattern_arrow(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        {_ast, result} =
          Macro.prewalk(ast, nil, fn
            {:try, _meta, [opts]} = node, nil when is_list(opts) ->
              case find_bad_after(opts) do
                {:ok, arrow_line} -> {node, {:ok, arrow_line}}
                :none -> {node, nil}
              end

            node, acc ->
              {node, acc}
          end)

        result || :none

      _ ->
        :none
    end
  end

  # Look through try options for an `after` clause containing `->` arrows.
  defp find_bad_after(opts) do
    Enum.find_value(opts, :none, fn
      {{:__block__, _meta, [:after]}, clauses} when is_list(clauses) ->
        case find_arrow_in_clauses(clauses) do
          {:ok, line} -> {:ok, line}
          :none -> nil
        end

      _ ->
        nil
    end)
  end

  # Check if the clauses list contains `->` arrows (which is invalid in `after`).
  defp find_arrow_in_clauses(clauses) do
    Enum.find_value(clauses, :none, fn
      {:->, meta, _args} ->
        {:ok, Keyword.get(meta, :line)}

      _ ->
        nil
    end)
  end

  # Source surgery: find the line with `->` after `after` and remove it,
  # de-indenting the body lines.
  defp remove_pattern_arrow(source) do
    lines = String.split(source, "\n")
    do_remove_pattern_arrow(lines, [], false)
    |> Enum.join("\n")
  end

  defp do_remove_pattern_arrow([], acc, _in_after), do: Enum.reverse(acc)

  defp do_remove_pattern_arrow([line | rest], acc, in_after) do
    trimmed = String.trim_leading(line)

    cond do
      # Found `after` keyword — enter after-clause mode
      Regex.match?(~r/^after\s*$/, trimmed) ->
        do_remove_pattern_arrow(rest, [line | acc], true)

      # In after clause, found a line ending with `->` (but not bare `->`)
      # This is the pattern line to remove
      in_after and String.ends_with?(trimmed, "->") and trimmed != "->" ->
        indent = get_indent_len(line)
        remove_and_deindent(rest, acc, indent)

      # In after clause, found a keyword that ends the after block
      in_after and Regex.match?(~r/^(end|rescue|catch)\b/, trimmed) ->
        do_remove_pattern_arrow(rest, [line | acc], false)

      # Otherwise, continue
      true ->
        do_remove_pattern_arrow(rest, [line | acc], in_after)
    end
  end

  # After removing the pattern line, de-indent body lines until we hit a line
  # at or below the pattern's indentation, or a block-ending keyword.
  defp remove_and_deindent([], acc, _pattern_indent), do: Enum.reverse(acc)

  defp remove_and_deindent([line | rest], acc, pattern_indent) do
    indent = get_indent_len(line)
    trimmed = String.trim_leading(line)

    cond do
      # Empty line — keep as-is
      trimmed == "" ->
        remove_and_deindent(rest, [line | acc], pattern_indent)

      # Hit a line at or below pattern indent — stop de-indenting, re-process
      indent <= pattern_indent ->
        do_remove_pattern_arrow([line | rest], acc, false)

      # Block-ending keywords at any indent within the after block
      Regex.match?(~r/^(end|rescue|catch)\b/, trimmed) ->
        do_remove_pattern_arrow([line | rest], acc, false)

      # Body line — de-indent by 2 spaces
      true ->
        deindented = deindent_line(line, 2)
        remove_and_deindent(rest, [deindented | acc], pattern_indent)
    end
  end

  defp deindent_line(line, count) do
    indent = get_indent(line)
    current = String.length(indent)

    if current > count do
      String.duplicate(" ", current - count) <> String.trim_leading(line)
    else
      String.trim_leading(line)
    end
  end

  defp get_indent_len(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> String.length(indent)
      _ -> 0
    end
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end
end
