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

  ## The safe core

  Reading malformed source line by line is guesswork: a `catch`/`after` sitting
  under an `end)` line may just as well be the legal `after` of a `receive`, or
  a word inside a heredoc, and the expression the wrap should start at is
  inferred from paren balance. So the repair is only ever offered when it is
  *demonstrably* the repair: the source must fail to parse, hold exactly one
  candidate site, and **parse successfully once wrapped**. Anything else is left
  untouched — no partial rewrite of code that still would not parse.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue
  alias Credence.SourceMask

  @impl true
  def analyze(source) do
    case repair(source) do
      {:ok, _fixed, line, keyword} ->
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
    case repair(source) do
      {:ok, fixed, _line, _keyword} -> fixed
      :none -> source
    end
  end

  # The single gate both `analyze/1` and `fix/1` ask, so the check can never
  # flag a case the fix would not touch.
  #
  # A repair is offered only when all of these hold:
  #
  #   * the source does not parse (the syntax phase's precondition);
  #   * exactly one `catch`/`after` line sits directly after an `end)` line —
  #     several sites mean several guesses, and the wraps would nest into each
  #     other, so the rule stands down;
  #   * wrapping that expression in `try do` makes the *whole* source parse.
  #
  # That last condition is what keeps the rule honest. Every way the line scan
  # can misread malformed text — a legal `receive ... after` whose previous line
  # happens to end in `end)`, the word `catch` inside a heredoc, a wrongly
  # guessed expression start — yields source that still does not parse, and is
  # dropped. The rule then either turns the file into valid Elixir or changes
  # nothing at all.
  defp repair(source) do
    with {:error, _} <- Sourceror.parse_string(source),
         lines = String.split(source, "\n"),
         shadow_lines = source |> SourceMask.mask() |> String.split("\n"),
         [{catch_idx, keyword}] <- candidates(lines, shadow_lines),
         {:ok, end_idx} <- find_preceding_end_paren(lines, shadow_lines, catch_idx - 1),
         expr_start_idx = find_expr_start(shadow_lines, end_idx),
         fixed = Enum.join(apply_try_wrap(lines, expr_start_idx, end_idx), "\n"),
         {:ok, _} <- Sourceror.parse_string(fixed) do
      {:ok, fixed, catch_idx + 1, keyword}
    else
      _ -> :none
    end
  end

  # Every `catch`/`after` line that follows an `end)` line, as `{index, keyword}`.
  defp candidates(lines, shadow_lines) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, idx} ->
      trimmed = String.trim_leading(line)

      with true <- Regex.match?(~r/^(catch|after)\b/, trimmed),
           {:ok, _end_idx} <- find_preceding_end_paren(lines, shadow_lines, idx - 1) do
        keyword = if String.starts_with?(trimmed, "catch"), do: "catch", else: "after"
        [{idx, keyword}]
      else
        _ -> []
      end
    end)
  end

  # Walk backwards from `idx`, skipping blank lines, looking for `end)`.
  defp find_preceding_end_paren(_lines, _shadow_lines, idx) when idx < 0, do: :none

  defp find_preceding_end_paren(lines, shadow_lines, idx) do
    line = Enum.at(lines, idx)
    shadow = shadow_lines |> Enum.at(idx) |> String.trim()

    cond do
      String.trim(line) == "" ->
        find_preceding_end_paren(lines, shadow_lines, idx - 1)

      Regex.match?(~r/\bend\)/, shadow) ->
        {:ok, idx}

      true ->
        :none
    end
  end

  # Find where the expression containing `end)` starts, by walking backwards
  # from the `end)` line and tracking parenthesis balance.
  defp find_expr_start(shadow_lines, end_idx) do
    line = Enum.at(shadow_lines, end_idx)
    opens = length(Regex.scan(~r/\(/, line))
    closes = length(Regex.scan(~r/\)/, line))
    net = opens - closes

    if net >= 0 do
      # Expression starts and ends on the same line as end)
      end_idx
    else
      # Walk backwards to find the matching open paren
      need = -net
      find_expr_start_backward(shadow_lines, end_idx - 1, need)
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
