defmodule Credence.Syntax.NoElifKeyword do
  @moduledoc """
  Detects and rewrites Python-style `elif` chains to idiomatic `cond`.

  LLMs translating from Python emit `elif` which is not valid Elixir syntax.
  The `elif` token causes the parser to misinterpret block boundaries,
  producing misleading "cannot invoke def/2 inside function/macro" errors.
  Converting `if`/`elif`/`else` chains to `cond` is behaviour-preserving and
  idiomatic.

  ## Bad (won't parse)

      if sequence <= last_seq do
        {:reply, {:ok, :duplicate}, state}
      elif sequence > last_seq + 1 do
        {:reply, {:ok, :buffered}, state}
      else
        {:reply, {:ok, :received}, state}
      end

  ## Good

      cond do
        sequence <= last_seq -> {:reply, {:ok, :duplicate}, state}
        sequence > last_seq + 1 -> {:reply, {:ok, :buffered}, state}
        true -> {:reply, {:ok, :received}, state}
      end
  """
  use Credence.Syntax.Rule
  alias Credence.Issue

  @elif_re ~r/^\s*elif\b/
  @if_do_re ~r/^\s*if\s+.+?\s+do\s*$/
  @else_re ~r/^\s*else\s*$/
  @end_re ~r/^\s*end\s*$/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(@elif_re, line) do
        [
          %Issue{
            rule: :no_elif_keyword,
            message: "Use `cond` instead of `elif`",
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

    case find_elif(lines) do
      {:ok, idx} ->
        rewrite_block(lines, idx) |> Enum.join("\n")

      :not_found ->
        source
    end
  end

  defp find_elif(lines) do
    Enum.find_value(Enum.with_index(lines), :not_found, fn {line, idx} ->
      if Regex.match?(@elif_re, line), do: {:ok, idx}, else: nil
    end)
  end

  defp rewrite_block(lines, elif_idx) do
    elif_indent = get_indent(Enum.at(lines, elif_idx))

    with {:ok, if_idx} <- scan_back_for_if(lines, elif_idx - 1, elif_indent),
         {:ok, branches, end_idx, else_branches} <-
           collect_branches(lines, if_idx, elif_idx, elif_indent) do
      if_start_indent = get_indent(Enum.at(lines, if_idx))
      cond_lines = build_cond(branches, else_branches, if_start_indent)
      Enum.take(lines, if_idx) ++ cond_lines ++ Enum.drop(lines, end_idx + 1)
    else
      _ -> lines
    end
  end

  defp scan_back_for_if(lines, idx, target_indent) when idx >= 0 do
    line = Enum.at(lines, idx)

    cond do
      Regex.match?(@if_do_re, line) and get_indent(line) == target_indent ->
        {:ok, idx}

      get_indent(line) < target_indent ->
        :not_found

      true ->
        scan_back_for_if(lines, idx - 1, target_indent)
    end
  end

  defp scan_back_for_if(_, _, _), do: :not_found

  defp collect_branches(lines, if_idx, elif_idx, elif_indent) do
    if_line = Enum.at(lines, if_idx)
    if_body = Enum.slice(lines, (if_idx + 1)..(elif_idx - 1))

    with {:ok, if_cond} <- extract_condition(if_line),
         {:ok, branches, rest_idx} <-
           collect_elif_branches(lines, elif_idx, elif_indent, [{if_cond, if_body}]) do
      case find_else_at_indent(lines, rest_idx, elif_indent) do
        {:ok, else_idx, end_idx} ->
          else_body = Enum.slice(lines, (else_idx + 1)..(end_idx - 1))
          {:ok, branches, end_idx, [{"true", else_body}]}

        {:not_found, end_idx} ->
          # No trailing `else`: an `if` without an `else` evaluates to `nil`
          # when no branch matches, but `cond` raises `CondClauseError`. Add an
          # explicit `true -> nil` clause so the rewrite keeps the `nil` answer.
          {:ok, branches, end_idx, [{"true", ["nil"]}]}
      end
    end
  end

  defp collect_elif_branches(lines, idx, target_indent, acc) do
    line = Enum.at(lines, idx)

    if Regex.match?(@elif_re, line) and get_indent(line) == target_indent do
      case extract_condition_from_elif(line) do
        {:ok, cond} ->
          next_idx = find_next_else(lines, idx + 1, target_indent)
          body = Enum.slice(lines, (idx + 1)..(next_idx - 1))
          collect_elif_branches(lines, next_idx, target_indent, acc ++ [{cond, body}])

        :error ->
          :bail
      end
    else
      {:ok, acc, idx}
    end
  end

  defp find_next_else(lines, idx, target_indent) do
    Enum.find_value(idx..(length(lines) - 1), length(lines) - 1, fn i ->
      line = Enum.at(lines, i)

      if line != nil and get_indent(line) == target_indent and
           (Regex.match?(@elif_re, line) or Regex.match?(@else_re, line) or
              Regex.match?(@end_re, line)) do
        i
      end
    end)
  end

  defp find_else_at_indent(lines, idx, target_indent) do
    line = Enum.at(lines, idx)

    if line != nil and get_indent(line) == target_indent do
      if Regex.match?(@else_re, String.trim_trailing(line)) do
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
      if line != nil and get_indent(line) == target_indent and Regex.match?(@end_re, line), do: i
    end)
  end

  defp build_cond(branches, else_branches, base_indent) do
    all_branches = branches ++ else_branches
    branch_indent = base_indent <> "  "

    branch_lines =
      Enum.flat_map(all_branches, fn {cond_str, body_lines} ->
        clean_body = Enum.reject(body_lines, &blank?/1)

        case clean_body do
          [] ->
            ["#{branch_indent}#{cond_str} ->"]

          _ ->
            first = "#{branch_indent}#{cond_str} -> #{String.trim(hd(clean_body))}"
            rest = Enum.map(tl(clean_body), &"#{branch_indent}  #{String.trim(&1)}")
            [first | rest]
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

  defp extract_condition(line) do
    case Regex.run(~r/^\s*if\s+(.+?)\s+do\s*$/, line) do
      [_, cond] -> {:ok, cond}
      _ -> :error
    end
  end

  defp extract_condition_from_elif(line) do
    case Regex.run(~r/^\s*elif\s+(.+?)\s+do\s*$/, line) do
      [_, cond] -> {:ok, cond}
      _ -> :error
    end
  end

  defp blank?(line), do: String.trim(line) == ""
end
