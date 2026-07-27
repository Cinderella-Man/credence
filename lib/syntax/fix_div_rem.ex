defmodule Credence.Syntax.FixDivRem do
  @moduledoc """
  Fixes `div` and `rem` used as infix operators (Python `//` and `%` style).

  LLMs frequently translate Python's `//` operator as `expr div expr`,
  but `div` is not an infix operator in Elixir — it must be called as
  `div(expr, expr)` or piped as `expr |> div(expr)`.

  ## Bad (won't parse)

      expected_sum = n * (n + 1) div 2

  ## Good

      expected_sum = div(n * (n + 1), 2)

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, so `div`/`rem` appearing
  inside a string literal or comment is invisible. Without that this rule
  mangled prose that merely mentioned the operator:

      IO.puts("use a div b")  ->  IO.puts("use Kernel.div(a, b")

  ## Function heads

  The left operand is bounded by an assignment (`x = …`) or a function head
  ending in `, do:`. Without the second of those, the lazy left-operand group
  swallowed the whole head:

      def f(n), do: n * (n + 1) div 2  ->  div(def f(n), do: n * (n + 1), 2)

  which is not merely broken — a later rule in the same reduce reshaped it into
  `div(def f(n), 2, do: n * (n + 1))`, which *parses*, so the phase declared
  success and shipped an entirely different program. Anything still carrying a
  `def`/`defp` head, a `when` guard or a `->` in the extracted left operand is
  declined outright.
  """
  use Credence.Syntax.Rule
  alias Credence.Issue
  alias Credence.SourceMask

  @operators ~w(div rem)

  # Tokens that must never survive inside an extracted left operand: each one
  # means the match reached past the start of the expression. `;` catches the
  # multi-statement line (`IO.puts("x"); n div 2`), where the lazy group would
  # otherwise swallow the earlier statement whole.
  @not_an_operand ~r/(?:^|\W)(?:def|defp|when|fn)(?:\W|$)|->|;/

  @impl true
  def analyze(source) do
    source
    |> SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{_line, shadow}, line_no} ->
      Enum.flat_map(@operators, fn op ->
        if infix_use?(shadow, op) do
          [build_issue(op, line_no)]
        else
          []
        end
      end)
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &fix_line/1)
  end

  defp infix_use?(line, op) do
    trimmed = String.trim(line)

    not String.starts_with?(trimmed, "#") and
      Regex.match?(infix_pattern(op), line)
  end

  # Matches: word/paren/digit SPACE div/rem SPACE word/digit
  # Does NOT match: |> div(, div(, .div
  defp infix_pattern(op) do
    ~r"(?<![|>.])\b\S+\)\s+#{op}\s+\w|(?<![|>.])\b\w+\s+#{op}\s+\w"
  end

  # The shadow is recomputed per operator because the previous rewrite shifts
  # every byte offset after it.
  defp fix_line(line) do
    Enum.reduce(@operators, line, fn op, current ->
      shadow = SourceMask.mask(current)

      if infix_use?(shadow, op) and not infix_in_capture?(shadow, op) do
        if infix_in_function_args?(shadow, op) do
          rewrite_infix_in_function_args(current, shadow, op)
        else
          rewrite_infix(current, shadow, op)
        end
      else
        current
      end
    end)
  end

  # Returns true if the infix usage of `op` is inside a function call's arguments.
  # E.g. `do_minto1((n - 1) div 2, 0)` — the `div` is inside the call to `do_minto1`.
  # The regex-based top-level rewrite can't handle this; we use `Kernel.op` instead.
  defp infix_in_function_args?(line, op) do
    case Regex.run(~r/\s+#{op}\s+/, line, return: :index) do
      [{op_pos, _len}] ->
        prefix = binary_part(line, 0, op_pos)
        in_function_args_prefix?(prefix)

      _ ->
        false
    end
  end

  defp in_function_args_prefix?(prefix) do
    # Scan prefix to see if there's an unclosed `(` preceded by a word char
    # (i.e., we're inside a function call's arguments).
    do_in_func_args?(prefix, false, false)
  end

  # End of prefix — are we inside a function call?
  defp do_in_func_args?(<<>>, inside_call, _), do: inside_call

  # Found `(` — check if preceded by a word char (= function call)
  defp do_in_func_args?(<<?(, rest::binary>>, inside_call, prev_is_word) do
    if prev_is_word do
      # Function call — track depth to find matching `)`
      do_func_args_close?(rest, 1, inside_call)
    else
      # Grouping paren — skip
      do_in_func_args?(rest, inside_call, false)
    end
  end

  defp do_in_func_args?(<<c, rest::binary>>, inside_call, _prev) do
    do_in_func_args?(rest, inside_call, word_char?(c))
  end

  # Track paren depth inside a function call until we find the matching `)`.
  # If we reach the end of prefix with unclosed parens, we're inside the call.
  defp do_func_args_close?(<<>>, depth, _), do: depth > 0

  defp do_func_args_close?(<<?(, rest::binary>>, depth, inside_call),
    do: do_func_args_close?(rest, depth + 1, inside_call)

  # Matched the function call's `)` — continue scanning, pass through inside_call
  defp do_func_args_close?(<<?), rest::binary>>, 1, inside_call),
    do: do_in_func_args?(rest, inside_call, false)

  defp do_func_args_close?(<<?), rest::binary>>, depth, inside_call),
    do: do_func_args_close?(rest, depth - 1, inside_call)

  defp do_func_args_close?(<<_c, rest::binary>>, depth, inside_call),
    do: do_func_args_close?(rest, depth, inside_call)

  # Returns true if the infix usage of `op` is inside a capture &(...)
  # The regex-based rewrite cannot handle capture context correctly,
  # so we skip the fix in that case (the issue is still reported by analyze).
  defp infix_in_capture?(line, op) do
    case Regex.run(~r/\s+#{op}\s+/, line, return: :index) do
      [{pos, _len}] ->
        prefix = binary_part(line, 0, pos)
        in_capture?(prefix)

      _ ->
        false
    end
  end

  defp in_capture?(prefix), do: do_in_capture?(prefix, [])

  defp do_in_capture?("", stack), do: :capture in stack

  defp do_in_capture?(<<?&, ?(, rest::binary>>, stack),
    do: do_in_capture?(rest, [:capture | stack])

  defp do_in_capture?(<<?(, rest::binary>>, stack), do: do_in_capture?(rest, [:regular | stack])
  defp do_in_capture?(<<?), rest::binary>>, [_ | stack]), do: do_in_capture?(rest, stack)
  # Unbalanced `)` with nothing on the stack — skip it and keep scanning
  # (a capture `&(` may still open later in the prefix).
  defp do_in_capture?(<<?), rest::binary>>, []), do: do_in_capture?(rest, [])
  defp do_in_capture?(<<_, rest::binary>>, stack), do: do_in_capture?(rest, stack)

  # Rewrites `prefix left_expr div right_expr` → `prefix div(left_expr, right_expr)`
  #
  # Strategy: find the assignment prefix (if any), then split on ` div `.
  # Left operand = everything between `=` (or line start) and the operator.
  # Right operand = everything after the operator to end of expression.
  defp rewrite_infix(line, shadow, op) do
    pattern = ~r/^(\s*(?:\w+\s*=\s*|defp?\s+.*?,\s*do:\s*)?)(.+?)\s+#{op}\s+(.+?)(\s*$)/

    case Regex.run(pattern, shadow, return: :index) do
      [_full, _prefix, {ls, ll}, {rs, rl}, _trailing] ->
        if declined?(binary_part(shadow, ls, ll)) do
          line
        else
          stop = rs + rl

          binary_part(line, 0, ls) <>
            "#{op}(#{binary_part(line, ls, ll)}, #{binary_part(line, rs, rl)})" <>
            binary_part(line, stop, byte_size(line) - stop)
        end

      nil ->
        line
    end
  end

  # Rewrites infix `op` inside a function call's arguments to `Kernel.op(left, right)`.
  # E.g. `do_minto1((n - 1) div 2, 0)` → `do_minto1(Kernel.div(n - 1, 2), 0)`
  defp rewrite_infix_in_function_args(line, shadow, op) do
    case Regex.run(~r/\s+#{op}\s+/, shadow, return: :index) do
      [{op_pos, op_len}] ->
        # Find left operand: scan backwards to find the start of the expression
        # at the current paren depth. Scanning runs on the shadow so a paren or
        # comma inside a string literal cannot be mistaken for a delimiter;
        # the operands themselves are sliced out of the real line.
        left_start = find_left_start(shadow, op_pos)
        left = String.trim(binary_part(line, left_start, op_pos - left_start))

        # Find right operand: scan forward from after the op to find end
        right_start = op_pos + op_len
        right_end = find_right_end(shadow, right_start)
        right = String.trim(binary_part(line, right_start, right_end - right_start))

        if declined?(binary_part(shadow, left_start, op_pos - left_start)) do
          line
        else
          prefix = binary_part(line, 0, left_start)
          suffix = binary_part(line, right_end, byte_size(line) - right_end)
          "#{prefix}Kernel.#{op}(#{left}, #{right})#{suffix}"
        end

      _ ->
        line
    end
  end

  # Scan backwards from op_pos to find the start of the left operand expression.
  # Handles nested parentheses.
  defp find_left_start(line, op_pos) do
    do_find_left_start(line, op_pos, 0, op_pos)
  end

  defp do_find_left_start(_line, 0, _depth, best), do: best

  defp do_find_left_start(line, pos, depth, best) do
    char = :binary.at(line, pos - 1)

    case char do
      ?) ->
        do_find_left_start(line, pos - 1, depth + 1, best)

      ?( when depth > 0 ->
        do_find_left_start(line, pos - 1, depth - 1, best)

      ?( when depth == 0 ->
        # Unmatched `(` — this is the boundary (could be function call or grouping)
        pos

      _ when depth == 0 and (char == ?, or char == ?\s or char == 9) ->
        # At depth 0, a comma or whitespace is a delimiter — stop
        best

      _ when depth == 0 ->
        do_find_left_start(line, pos - 1, 0, pos - 1)

      _ ->
        do_find_left_start(line, pos - 1, depth, best)
    end
  end

  # An extracted left operand is only usable if it is a self-contained
  # expression: no keyword that starts a larger construct, and balanced
  # delimiters. Unbalanced ones mean the lazy group started inside a call that
  # opened earlier on the line.
  defp declined?(operand) do
    Regex.match?(@not_an_operand, operand) or not balanced?(operand)
  end

  defp balanced?(operand) do
    operand
    |> :binary.bin_to_list()
    |> Enum.reduce_while(0, fn
      c, depth when c in [?(, ?[, ?{] -> {:cont, depth + 1}
      c, depth when c in [?), ?], ?}] and depth == 0 -> {:halt, :unbalanced}
      c, depth when c in [?), ?], ?}] -> {:cont, depth - 1}
      _, depth -> {:cont, depth}
    end)
    |> Kernel.==(0)
  end

  defp word_char?(c) do
    (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or (c >= ?0 and c <= ?9) or c == ?_
  end

  # Scan forward from after the op to find the end of the right operand.
  # Returns the position after the last char of the right operand.
  defp find_right_end(line, start) do
    do_find_right_end(line, start, byte_size(line), 0, start)
  end

  defp do_find_right_end(_line, pos, len, _depth, _best) when pos >= len, do: pos

  defp do_find_right_end(line, pos, len, depth, _best) do
    char = :binary.at(line, pos)

    case char do
      ?( ->
        do_find_right_end(line, pos + 1, len, depth + 1, pos + 1)

      ?) when depth > 0 ->
        do_find_right_end(line, pos + 1, len, depth - 1, pos + 1)

      ?) when depth == 0 ->
        # Unmatched `)` — this ends the arg
        pos

      ?, when depth == 0 ->
        # Comma at depth 0 — this ends the arg
        pos

      _ ->
        do_find_right_end(line, pos + 1, len, depth, pos + 1)
    end
  end

  defp build_issue(op, line) do
    %Issue{
      rule: :"infix_#{op}",
      message:
        "`#{op}` cannot be used as an infix operator in Elixir. " <>
          "Use `#{op}(a, b)` function call syntax instead.",
      meta: %{line: line}
    }
  end
end
