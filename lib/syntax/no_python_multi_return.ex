defmodule Credence.Syntax.NoPythonMultiReturn do
  @moduledoc """
  Fixes Python-style bare comma multi-return expressions.

  LLMs translating Python's `return a, b` produce `a, b` at the top level of
  an Elixir function body. A bare comma at nesting depth 0 is a syntax error
  in Elixir — the parser reports "syntax error before: ','".

  The fix deterministically wraps the comma-separated expressions in a tuple:
  `a, b` becomes `{a, b}`.

  ## Bad (won't parse)

      {:ok, new_state}, [event]

  ## Good

      {{:ok, new_state}, [event]}
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if bare_comma_at_depth_zero?(line) do
        [
          %Issue{
            rule: :no_python_multi_return,
            message:
              "Bare comma multi-return is not valid Elixir. " <>
                "Wrap expressions in a tuple `{a, b}` instead.",
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
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &fix_line/1)
  end

  # Returns true when `line` contains a comma at delimiter-nesting depth 0
  # (outside parens, brackets, braces, strings, and heredocs).
  defp bare_comma_at_depth_zero?(line) do
    line
    |> split_at_depth_zero_commas()
    |> length()
    |> Kernel.>(1)
  end

  defp fix_line(line) do
    parts = split_at_depth_zero_commas(line)

    case parts do
      [_single] ->
        line

      multiple ->
        joined = Enum.join(multiple, ",")
        {leading, rest} = split_leading_ws(joined)
        leading <> "{" <> rest <> "}"
    end
  end

  # Split a string into {leading_whitespace, rest}.
  defp split_leading_ws(str) do
    trimmed = String.trim_leading(str)
    len = byte_size(str) - byte_size(trimmed)
    {binary_part(str, 0, len), trimmed}
  end

  # Split `line` at every comma that sits at depth 0. Returns a list of
  # segments — one element means no bare comma was found.
  defp split_at_depth_zero_commas(line) do
    {segments, current, _depth, _in_str} =
      line
      |> String.to_charlist()
      |> Enum.reduce({[], [], 0, nil}, fn ch, {segs, cur, depth, in_str} ->
        cond do
          # Inside a string/char literal — skip until closing quote
          in_str != nil ->
            case ch do
              ^in_str -> {segs, cur ++ [ch], depth, nil}
              ?\\ -> {segs, cur ++ [ch], depth, in_str}
              _ -> {segs, cur ++ [ch], depth, in_str}
            end

          # Start of a string or char literal
          ch in [?", ?'] ->
            {segs, cur ++ [ch], depth, ch}

          # Open delimiter — increase depth
          ch in [?(, ?[, ?{] ->
            {segs, cur ++ [ch], depth + 1, nil}

          # Close delimiter — decrease depth (guard against underflow)
          ch in [?), ?], ?}] ->
            new_depth = max(depth - 1, 0)
            {segs, cur ++ [ch], new_depth, nil}

          # Bare comma at depth 0 — split here
          ch == ?, and depth == 0 ->
            {segs ++ [cur], [], 0, nil}

          # Any other character
          true ->
            {segs, cur ++ [ch], depth, nil}
        end
      end)

    # Append the final segment
    segments ++ [current]
  end
end
