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
    |> find_bare_comma_lines()
    |> Enum.map(fn line_no ->
      %Issue{
        rule: :no_python_multi_return,
        message:
          "Bare comma multi-return is not valid Elixir. " <>
            "Wrap expressions in a tuple `{a, b}` instead.",
        meta: %{line: line_no}
      }
    end)
  end

  @impl true
  def fix(source) do
    flagged = MapSet.new(find_bare_comma_lines(source))

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {line, line_no} ->
      if MapSet.member?(flagged, line_no) do
        fix_line(line)
      else
        line
      end
    end)
  end

  # Walk the entire source to find lines that have bare commas at global
  # depth 0.  This avoids the false-positive where a comma inside a
  # multi-line `%{}`, `[]`, or `()` is treated as depth-0 because each
  # line was previously analysed in isolation.
  defp find_bare_comma_lines(source) do
    line_depths = compute_line_start_depths(source)

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      start_depth = Map.get(line_depths, line_no, 0)

      if start_depth == 0 and
           not comment_line?(line) and
           not has_left_arrow_at_depth_zero?(line) and
           has_bare_comma?(line) do
        [line_no]
      else
        []
      end
    end)
  end

  # ── Cross-line depth tracking ──────────────────────────────────────────

  # Returns %{line_no => depth_at_start_of_line} by walking the entire source,
  # properly accounting for string literals and comments.
  defp compute_line_start_depths(source) do
    source
    |> String.to_charlist()
    |> walk_depths(%{1 => 0}, 0, 1, nil)
  end

  # EOF
  defp walk_depths([], depths, _depth, _line, _ctx), do: depths

  # Newline — record depth for the next line
  defp walk_depths([?\n | rest], depths, depth, line, ctx) do
    walk_depths(rest, Map.put(depths, line + 1, depth), depth, line + 1, ctx)
  end

  # Inside a comment — skip until newline (handled above)
  defp walk_depths([_ | rest], depths, depth, line, :comment) do
    walk_depths(rest, depths, depth, line, :comment)
  end

  # Escape inside a string — skip the escaped character
  defp walk_depths([?\\, escaped | rest], depths, depth, line, ctx)
       when ctx == ?" or ctx == ?' do
    # If the escaped char is a newline, still track the line
    {depths, depth, line} =
      if escaped == ?\n,
        do: {Map.put(depths, line + 1, depth), depth, line + 1},
        else: {depths, depth, line}

    walk_depths(rest, depths, depth, line, ctx)
  end

  # Close string
  defp walk_depths([q | rest], depths, depth, line, ctx)
       when (ctx == ?" or ctx == ?') and q == ctx do
    walk_depths(rest, depths, depth, line, nil)
  end

  # Inside string — skip
  defp walk_depths([_ | rest], depths, depth, line, ctx)
       when ctx == ?" or ctx == ?' do
    walk_depths(rest, depths, depth, line, ctx)
  end

  # Start of comment
  defp walk_depths([?# | rest], depths, depth, line, nil) do
    walk_depths(rest, depths, depth, line, :comment)
  end

  # Start of string
  defp walk_depths([q | rest], depths, depth, line, nil)
       when q == ?" or q == ?' do
    walk_depths(rest, depths, depth, line, q)
  end

  # Open delimiter
  defp walk_depths([ch | rest], depths, depth, line, nil)
       when ch == ?( or ch == ?[ or ch == ?{ do
    walk_depths(rest, depths, depth + 1, line, nil)
  end

  # Close delimiter
  defp walk_depths([ch | rest], depths, depth, line, nil)
       when ch == ?) or ch == ?] or ch == ?} do
    walk_depths(rest, depths, max(depth - 1, 0), line, nil)
  end

  # Any other character
  defp walk_depths([_ | rest], depths, depth, line, ctx) do
    walk_depths(rest, depths, depth, line, ctx)
  end

  # ── Bare-comma detection (single-line, starting from depth 0) ─────────

  # Returns true when `line` contains a bare comma at depth 0 that is NOT
  # a keyword entry separator, catch/rescue arrow, or with/for clause.
  defp has_bare_comma?(line) do
    line
    |> split_at_depth_zero_commas()
    |> length()
    |> Kernel.>(1)
  end

  # Returns true when the line contains `<-` at depth 0, signalling a
  # `with`/`for` clause whose commas are clause separators, not bare
  # multi-returns.
  defp has_left_arrow_at_depth_zero?(line) do
    check_left_arrow(String.to_charlist(line), 0, nil)
  end

  # Found `<-` at depth 0 outside a string
  defp check_left_arrow([?<, ?- | _rest], 0, nil), do: true

  # EOF
  defp check_left_arrow([], _depth, _ctx), do: false

  # Newline
  defp check_left_arrow([?\n | rest], depth, _ctx) do
    check_left_arrow(rest, depth, nil)
  end

  # Inside comment — skip
  defp check_left_arrow([_ | rest], depth, :comment) do
    check_left_arrow(rest, depth, :comment)
  end

  # Escape inside string — skip escaped character
  defp check_left_arrow([?\\, _escaped | rest], depth, ctx)
       when ctx == ?" or ctx == ?' do
    check_left_arrow(rest, depth, ctx)
  end

  # Close string
  defp check_left_arrow([q | rest], depth, ctx)
       when (ctx == ?" or ctx == ?') and q == ctx do
    check_left_arrow(rest, depth, nil)
  end

  # Inside string — skip
  defp check_left_arrow([_ | rest], depth, ctx)
       when ctx == ?" or ctx == ?' do
    check_left_arrow(rest, depth, ctx)
  end

  # Start of comment
  defp check_left_arrow([?# | rest], depth, nil) do
    check_left_arrow(rest, depth, :comment)
  end

  # Start of string
  defp check_left_arrow([q | rest], depth, nil)
       when q == ?" or q == ?' do
    check_left_arrow(rest, depth, q)
  end

  # Open delimiter
  defp check_left_arrow([ch | rest], depth, nil)
       when ch == ?( or ch == ?[ or ch == ?{ do
    check_left_arrow(rest, depth + 1, nil)
  end

  # Close delimiter
  defp check_left_arrow([ch | rest], depth, nil)
       when ch == ?) or ch == ?] or ch == ?} do
    check_left_arrow(rest, max(depth - 1, 0), nil)
  end

  # Any other character
  defp check_left_arrow([_ | rest], depth, ctx) do
    check_left_arrow(rest, depth, ctx)
  end

  # ── Fix helpers ────────────────────────────────────────────────────────

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

          # Bare comma at depth 0 — split here unless a keyword key, arrow,
          # or function-call-without-parens precedes it.
          ch == ?, and depth == 0 ->
            if keyword_or_arrow_ahead?(remaining) or function_call_before?(cur) do
              # Keep comma with current segment (keyword entry, clause pattern,
              # or paren-less function call like `raise ArgumentError, "msg"`)
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

  # Returns true when the accumulated text before a depth-zero comma starts
  # with a lowercase identifier followed by whitespace and then content (not
  # `=`).  This indicates a paren-less function call, e.g.:
  #
  #     raise ArgumentError, "msg"  →  current = 'raise ArgumentError'
  #     send dest, msg              →  current = 'send dest'
  #
  # Without this check the rule would wrap these in a tuple, producing
  # `{raise ArgumentError, "msg"}` which is a syntax error.
  defp function_call_before?(current_chars) do
    case Enum.drop_while(current_chars, &(&1 == ?\s or &1 == ?\t)) do
      [ch | rest] when ch in ?a..?z or ch == ?_ ->
        # Consume the identifier (letters, digits, underscores, dots)
        {_id, after_id} = Enum.split_while([ch | rest], fn c ->
          c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ or c == ?.
        end)
        # Skip whitespace after the identifier
        after_ws = Enum.drop_while(after_id, &(&1 == ?\s or &1 == ?\t))
        # Must have content after the identifier, and it must not be an
        # assignment (which would indicate `var = expr, ...` not a function call)
        case after_ws do
          [] -> false
          [?= | _] -> false
          _ -> true
        end
      _ -> false
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
