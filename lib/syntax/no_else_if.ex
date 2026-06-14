defmodule Credence.Syntax.NoElseIf do
  @moduledoc """
  Detects and rewrites Python-style `else if` (two words) chains to idiomatic `cond`.

  LLMs translating from Python emit `else if` (two words) which in Elixir parses
  as `else` + nested `if` needing its own `end`, causing persistent
  `TokenMissingError`. Converting `else if` chains to `cond` is
  behaviour-preserving and idiomatic.

  ## Bad (won't parse as intended)

      if n == 0 do
        list
      else if n >= length(list) do
        []
      else
        List.take(list, length(list) - n)
      end

  ## Good

      cond do
        n == 0 -> list
        n >= length(list) -> []
        true -> List.take(list, length(list) - n)
      end
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @else_if_re ~r/^\s*else\s+if\b/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@else_if_re, line) do
        [
          %Issue{
            rule: :no_else_if,
            message: "Use `cond` instead of `else if`",
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

    case find_else_if(lines) do
      {:ok, idx} ->
        rewrite_block(lines, idx) |> Enum.join("\n")

      :not_found ->
        source
    end
  end

  defp find_else_if(lines) do
    Enum.find_value(Enum.with_index(lines), :not_found, fn {line, idx} ->
      if Regex.match?(@else_if_re, line), do: {:ok, idx}, else: nil
    end)
  end

  defp rewrite_block(lines, else_if_idx) do
    else_if_indent = get_indent(Enum.at(lines, else_if_idx))

    case scan_back_for_if(lines, else_if_idx - 1, else_if_indent) do
      {:ok, if_idx} ->
        {branches, end_idx, else_branches} =
          collect_branches(lines, if_idx, else_if_idx, else_if_indent)

        if_start_indent = get_indent(Enum.at(lines, if_idx))
        cond_lines = build_cond(branches, else_branches, if_start_indent)
        Enum.take(lines, if_idx) ++ cond_lines ++ Enum.drop(lines, end_idx + 1)

      :not_found ->
        lines
    end
  end

  defp scan_back_for_if(lines, idx, target_indent) when idx >= 0 do
    line = Enum.at(lines, idx)

    cond do
      if_line?(line) and get_indent(line) == target_indent ->
        {:ok, idx}

      get_indent(line) < target_indent ->
        :not_found

      true ->
        scan_back_for_if(lines, idx - 1, target_indent)
    end
  end

  defp scan_back_for_if(_, _, _), do: :not_found

  defp collect_branches(lines, if_idx, else_if_idx, else_if_indent) do
    if_line = Enum.at(lines, if_idx)
    if_cond = extract_condition(if_line)
    if_body = Enum.slice(lines, (if_idx + 1)..(else_if_idx - 1))
    first_branch = [{if_cond, if_body}]

    {branches, rest_idx} =
      collect_else_if_branches(lines, else_if_idx, else_if_indent, first_branch)

    case find_else_at_indent(lines, rest_idx, else_if_indent) do
      {:ok, else_idx, end_idx} ->
        else_body = Enum.slice(lines, (else_idx + 1)..(end_idx - 1))
        {branches, end_idx, [{"true", else_body}]}

      {:not_found, end_idx} ->
        {branches, end_idx, []}
    end
  end

  defp collect_else_if_branches(lines, idx, target_indent, acc) do
    line = Enum.at(lines, idx)

    if Regex.match?(@else_if_re, line) and get_indent(line) == target_indent do
      cond = extract_else_if_condition(line)
      next_idx = find_next_else(lines, idx + 1, target_indent)
      body = Enum.slice(lines, (idx + 1)..(next_idx - 1))
      collect_else_if_branches(lines, next_idx, target_indent, acc ++ [{cond, body}])
    else
      {acc, idx}
    end
  end

  defp find_next_else(lines, idx, target_indent) do
    Enum.find_value(idx..(length(lines) - 1), length(lines) - 1, fn i ->
      line = Enum.at(lines, i)

      if line != nil and get_indent(line) == target_indent and
           (Regex.match?(~r/^\s*else\b/, line) or if_end?(line)) do
        i
      end
    end)
  end

  defp find_else_at_indent(lines, idx, target_indent) do
    line = Enum.at(lines, idx)

    if line != nil and get_indent(line) == target_indent do
      if Regex.match?(~r/^\s*else\s*$/, String.trim_trailing(line)) do
        end_idx = find_end(lines, idx + 1, target_indent)
        {:ok, idx, end_idx}
      else
        {:not_found, idx}
      end
    else
      {:not_found, idx}
    end
  end

  defp find_end(lines, idx, target_indent) do
    Enum.find_value(idx..(length(lines) - 1), length(lines) - 1, fn i ->
      line = Enum.at(lines, i)
      if line != nil and get_indent(line) == target_indent and if_end?(line), do: i
    end)
  end

  defp build_cond(branches, else_branches, base_indent) do
    all_branches = branches ++ else_branches
    body_indent = base_indent <> "  "

    branch_lines =
      Enum.flat_map(all_branches, fn {cond_str, body_lines} ->
        clean_body = Enum.reject(body_lines, &blank?/1)
        {expr_lines, trailing_comments} = Enum.split_with(clean_body, &(not comment?(&1)))

        case expr_lines do
          [] ->
            # No expression lines — only comments (or nothing). A `cond` clause
            # still needs a value after `->`, so insert `nil` and keep comments
            # below it; otherwise the rewrite produces a bodyless `true ->` that
            # the validator rejects and reverts.
            case trailing_comments do
              [] ->
                ["#{body_indent}#{cond_str} ->"]

              _ ->
                nil_line = "#{body_indent}#{cond_str} -> nil"
                comment_tail = Enum.map(trailing_comments, &"#{body_indent}  #{String.trim(&1)}")
                [nil_line | comment_tail]
            end

          _ ->
            first = "#{body_indent}#{cond_str} -> #{String.trim(hd(expr_lines))}"
            rest = Enum.map(tl(expr_lines), &"#{body_indent}  #{String.trim(&1)}")
            comment_tail = Enum.map(trailing_comments, &"#{body_indent}  #{String.trim(&1)}")
            [first | rest] ++ comment_tail
        end
      end)

    ["#{base_indent}cond do"] ++ branch_lines ++ ["#{base_indent}end"]
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  defp if_line?(line), do: Regex.match?(~r/^\s*if\b/, line)
  defp if_end?(line), do: Regex.match?(~r/^\s*end\s*$/, line)

  defp extract_condition(line) do
    case Regex.run(~r/^\s*if\s+(.+?)\s+do\s*$/, line) do
      [_, cond] -> cond
      _ -> "true"
    end
  end

  defp extract_else_if_condition(line) do
    case Regex.run(~r/^\s*else\s+if\s+(.+?)\s+do\s*$/, line) do
      [_, cond] -> cond
      _ -> "true"
    end
  end

  defp blank?(line), do: String.trim(line) == ""
  defp comment?(line), do: Regex.match?(~r/^\s*#/, line)
end
