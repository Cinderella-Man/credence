defmodule Credence.Syntax.NoCatchAfterAnonFn do
  @moduledoc """
  Detects and repairs `catch`/`after` clauses placed directly after `fn...end`
  closings.

  LLMs repeatedly place `catch`/`after` clauses directly after `fn...end`
  closings (as if `fn` were a block keyword like `case`/`receive`), producing a
  mismatched-delimiter syntax error. The parser reports "unexpected reserved
  word: end" with a hint about a missing `do`.

  The deterministic fix wraps the preceding expression in `try do...end` so
  `catch`/`after` has a legal block to attach to.

  ## Bad (won't parse — syntax error at orphaned `end`)

      Enum.map([1, 2, 3], fn x ->
        x + 1
      end)
      catch
        value -> value
      end

  ## Good

      try do
        Enum.map([1, 2, 3], fn x ->
          x + 1
        end)
      catch
        value -> value
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @impl true
  def analyze(source) do
    case detect_pattern(source) do
      {:ok, line, keyword} ->
        [
          %Issue{
            rule: :no_catch_after_anon_fn,
            message: "`#{keyword}` after anonymous function `end)` — wrap in `try` instead",
            meta: %{line: line}
          }
        ]

      :none ->
        []
    end
  end

  @impl true
  def fix(source) do
    case detect_pattern(source) do
      {:ok, catch_line_no, _keyword} ->
        lines = String.split(source, "\n")
        catch_idx = catch_line_no - 1

        case find_preceding_end_paren(lines, catch_idx - 1) do
          {:ok, end_idx} ->
            expr_start_idx = find_expr_start(lines, end_idx)
            fixed_lines = apply_try_wrap(lines, expr_start_idx, end_idx)
            fixed = Enum.join(fixed_lines, "\n")
            if fixed != source, do: fix(fixed), else: source

          :none ->
            source
        end

      :none ->
        source
    end
  end

  # Detect the pattern: source fails to parse AND contains `catch`/`after` after `end)`.
  defp detect_pattern(source) do
    case Code.string_to_quoted(source) do
      {:ok, _} ->
        :none

      {:error, _} ->
        lines = String.split(source, "\n")
        find_catch_after_end_paren(lines)
    end
  end

  # Scan lines for `catch` or `after` keyword that follows an `end)` line.
  defp find_catch_after_end_paren(lines) do
    lines
    |> Enum.with_index()
    |> Enum.find_value(:none, fn {line, idx} ->
      trimmed = String.trim_leading(line)

      if Regex.match?(~r/^(catch|after)\b/, trimmed) do
        case find_preceding_end_paren(lines, idx - 1) do
          {:ok, _end_idx} ->
            keyword = if String.starts_with?(trimmed, "catch"), do: "catch", else: "after"
            {:ok, idx + 1, keyword}

          :none ->
            nil
        end
      end
    end)
  end

  # Walk backwards from `idx`, skipping blank lines, looking for `end)`.
  defp find_preceding_end_paren(_lines, idx) when idx < 0, do: :none

  defp find_preceding_end_paren(lines, idx) do
    line = Enum.at(lines, idx)
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        find_preceding_end_paren(lines, idx - 1)

      Regex.match?(~r/\bend\)/, trimmed) ->
        {:ok, idx}

      true ->
        :none
    end
  end

  # Find where the expression containing `end)` starts, by walking backwards
  # from the `end)` line and tracking parenthesis balance.
  defp find_expr_start(lines, end_idx) do
    line = Enum.at(lines, end_idx)
    opens = length(Regex.scan(~r/\(/, line))
    closes = length(Regex.scan(~r/\)/, line))
    net = opens - closes

    if net >= 0 do
      # Expression starts and ends on the same line as end)
      end_idx
    else
      # Walk backwards to find the matching open paren
      need = -net
      find_expr_start_backward(lines, end_idx - 1, need)
    end
  end

  defp find_expr_start_backward(_lines, idx, _need) when idx < 0, do: 0

  defp find_expr_start_backward(lines, idx, need) do
    line = Enum.at(lines, idx)
    opens = length(Regex.scan(~r/\(/, line))
    closes = length(Regex.scan(~r/\)/, line))
    new_need = need - (opens - closes)

    if new_need <= 0 do
      idx
    else
      find_expr_start_backward(lines, idx - 1, new_need)
    end
  end

  # Insert `try do` before the expression and indent the expression block by 2.
  defp apply_try_wrap(lines, expr_start_idx, end_idx) do
    expr_indent = get_indent(Enum.at(lines, expr_start_idx))

    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, idx} ->
      cond do
        idx == expr_start_idx ->
          [expr_indent <> "try do", "  " <> line]

        idx > expr_start_idx and idx <= end_idx ->
          ["  " <> line]

        true ->
          [line]
      end
    end)
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end
end
