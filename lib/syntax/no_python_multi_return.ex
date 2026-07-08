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
    not comment_line?(line) and
      (line
       |> split_at_depth_zero_commas()
       |> length()
       |> Kernel.>(1))
  end

  defp fix_line(line) do
    if comment_line?(line) do
      line
    else
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
  end

  # A line is a comment when its first non-whitespace character is `#`.
  defp comment_line?(line) do
    case String.trim_leading(line) do
      <<?#, _::binary>> -> true
      _ -> false
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
  #
  # Two lookaheads prevent over-firing:
  #   1. Keyword syntax — if the next non-space text starts with a keyword key
  #      (`word:` or `:"string":`), the comma is a keyword entry separator, not
  #      a bare multi-return. Keep it with the current segment.
  #   2. Catch/rescue clause — if `->` appears before the next depth-zero comma,
  #      the comma separates patterns in a clause head, not a bare multi-return.
  defp split_at_depth_zero_commas(line) do
    chars = String.to_charlist(line)
    # Track remaining chars so the lookahead at each comma is accurate
    {segments, current, _depth, _in_str, _remaining} =
      Enum.reduce(chars, {[], [], 0, nil, safe_tl(chars)}, fn ch, {segs, cur, depth, in_str, remaining} ->
        tail = safe_tl(remaining)

        cond do
          # Inside a string/char literal — skip until closing quote
          in_str != nil ->
            case ch do
              ^in_str -> {segs, cur ++ [ch], depth, nil, tail}
              ?\\ -> {segs, cur ++ [ch], depth, in_str, tail}
              _ -> {segs, cur ++ [ch], depth, in_str, tail}
            end

          # Start of a string or char literal
          ch in [?", ?'] ->
            {segs, cur ++ [ch], depth, ch, tail}

          # Open delimiter — increase depth
          ch in [?(, ?[, ?{] ->
            {segs, cur ++ [ch], depth + 1, nil, tail}

          # Close delimiter — decrease depth (guard against underflow)
          ch in [?), ?], ?}] ->
            new_depth = max(depth - 1, 0)
            {segs, cur ++ [ch], new_depth, nil, tail}

          # Bare comma at depth 0 — split here unless a keyword key or arrow follows
          ch == ?, and depth == 0 ->
            if keyword_or_arrow_ahead?(remaining) do
              # Keep comma with current segment (keyword entry or clause pattern)
              {segs, cur ++ [ch], 0, nil, tail}
            else
              {segs ++ [cur], [], 0, nil, tail}
            end

          # Any other character
          true ->
            {segs, cur ++ [ch], depth, nil, tail}
        end
      end)

    # Append the final segment
    segments ++ [current]
  end

  defp safe_tl([]), do: []
  defp safe_tl([_ | t]), do: t

  # Returns true when, after the current comma, the next non-space text is a
  # keyword key (`word:` or `:"string":`) OR `->` appears before the next
  # depth-zero comma.
  defp keyword_or_arrow_ahead?(remaining_chars) do
    # Skip whitespace after the comma
    after_ws = Enum.drop_while(remaining_chars, &(&1 == ?\s))

    case after_ws do
      [] ->
        false

      # Atom key like :exit — not a keyword entry, check for arrow
      [?: | _rest] ->
        arrow_ahead?(after_ws)

      # Possible keyword key: word_char+
      [ch | _] when ch in ?a..?z or ch in ?A..?Z or ch == ?_ ->
        keyword_ahead?(after_ws) or arrow_ahead?(after_ws)

      _ ->
        arrow_ahead?(after_ws)
    end
  end

  # Check if `chars` starts with a keyword key pattern: word+ `:` or `:"` string `":`
  defp keyword_ahead?(chars) do
    # Consume word characters
    {word, rest} = Enum.split_while(chars, fn ch ->
      ch in ?a..?z or ch in ?A..?Z or ch in ?0..?9 or ch == ?_
    end)

    case rest do
      [?: | _] when word != [] -> true
      _ -> false
    end
  end

  # Check if `->` appears in `chars` before the next depth-zero comma.
  defp arrow_ahead?(chars), do: arrow_ahead?(chars, 0)

  defp arrow_ahead?([], _depth), do: false
  defp arrow_ahead?([?, | _], 0), do: false
  defp arrow_ahead?([?-, ?> | _rest], _depth), do: true

  defp arrow_ahead?([ch | rest], depth) when ch in [?(, ?[, ?{],
    do: arrow_ahead?(rest, depth + 1)

  defp arrow_ahead?([ch | rest], depth) when ch in [?), ?], ?}],
    do: arrow_ahead?(rest, max(depth - 1, 0))

  # Skip string/char literals
  defp arrow_ahead?([q | rest], depth) when q in [?", ?'],
    do: arrow_ahead?(skip_string(rest, q), depth)

  defp arrow_ahead?([_ | rest], depth), do: arrow_ahead?(rest, depth)

  defp skip_string([], _q), do: []
  defp skip_string([?\\, _ | rest], q), do: skip_string(rest, q)
  defp skip_string([q | rest], q), do: rest
  defp skip_string([_ | rest], q), do: skip_string(rest, q)
end
