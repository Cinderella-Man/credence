defmodule Credence.Syntax.FixPythonAugmentedAssignment do
  @moduledoc """
  Replaces Python's augmented assignment operators (`+=`, `-=`, `*=`, `/=`)
  with Elixir's rebinding syntax.

  LLMs translating from Python carry over augmented assignment operators.
  In Elixir, `+=` and friends are not valid — variables are rebound with `=`,
  so `x += expr` must become `x = x + (expr)`.

  This is a Syntax rule because `x += y` won't parse in Elixir.

  ## Detected patterns

  Only a **standalone statement** whose left-hand side is a bare variable is
  rewritten — the line must be `<indent><identifier> <op>= <expr>` and nothing
  else:

      count += 1                x -= delta
      total *= factor           value /= divisor

  ## Why the right-hand side is parenthesised

  Python's `x op= expr` means `x = x op (expr)` — the whole right-hand side is
  one operand. A naive textual rewrite to `x = x op expr` changes the answer
  whenever `expr` contains a lower-precedence operator: `x *= a + b` would
  become `x = x * a + b` (`(x*a)+b`) instead of `x = x * (a + b)`. Wrapping the
  right-hand side in parentheses keeps the result bit-identical to Python
  semantics for *every* expression.

  ## Not flagged

  Anything that isn't a bare-variable augmented assignment is left untouched, so
  no valid code is ever corrupted:

  - operators appearing inside string literals (`x = "a += b"`) — the `op=` is
    not the line's leading token, so it never matches;
  - qualified or indexed targets (`map.count += 1`, `arr[i] += 1`) — Elixir
    can't rebind those anyway, and a bare-identifier rewrite would be wrong;
  - comment lines.

  `+=`, `-=`, `*=`, and `/=` are not substrings of any valid Elixir operator,
  so an anchored, leading-identifier match cannot fire on legitimate code.

  ## Only real code is rewritten

  Matching runs against a `Credence.SourceMask` shadow, not the raw line, so
  comments, strings, sigils and heredoc bodies are invisible to the pattern, and
  the bytes emitted are always read back out of the real line.

  The "Not flagged" list above was true only by accident, and the accident had
  already run out. Its first bullet argues that a literal is safe because `op=`
  is "not the line's leading token" — true of `x = "a += b"`, and irrelevant
  inside a heredoc, where a documentation line may begin with exactly the shape
  this rule matches. The `## Detected patterns` and `## Bad` blocks below are
  such lines, and this rule rewrote all four of them (docs/22 T3.10), turning its
  own examples of the input into examples of the output.

  ## Where the right-hand side stops

  The right-hand side runs to the end of the line, which means a trailing comment
  used to be captured as part of the expression: `count += 1  # total` became
  `count = count + (1  # total)`, putting the closing paren inside the comment so
  the output did not parse at all. The shadow answers this too — a `#` comment is
  blanked to the end of the line, so the expression ends where the trailing run of
  blanked bytes begins, provided the raw line really has a `#` there. A trailing
  *string* is blanked the same way but is part of the expression, and the byte in
  the raw line is what tells the two apart. The comment is preserved after the
  rewritten statement rather than swallowed by it.

  ## Bad

      count += Map.get(freq, key, 0)
      total *= factor

  ## Good

      count = count + (Map.get(freq, key, 0))
      total = total * (factor)
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Anchored at the start of the line: optional indentation, a bare variable,
  # one of the arithmetic ops immediately followed by `=`, then a non-empty
  # right-hand side that runs to the end of the line. Trailing whitespace is
  # trimmed out of the captured expression.
  #
  #   group 1: leading indentation
  #   group 2: variable name
  #   group 3: operator character (+, -, *, /)
  #   group 4: right-hand side expression
  @augmented_pattern ~r/^(\s*)([A-Za-z_]\w*)\s*([-+*\/])=\s*(\S.*?)\s*$/

  # `Credence.SourceMask` blanks every non-code byte to this one.
  @blank 0x01

  @impl true
  def analyze(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{line, shadow}, line_no} ->
      case captures(line, shadow) do
        {_indent, _var, op, _rhs, _tail} -> [build_issue(line_no, op)]
        nil -> []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> Credence.SourceMask.lines()
    |> Enum.map_join("\n", fn {line, shadow} -> fix_line(line, shadow) end)
  end

  defp fix_line(line, shadow) do
    case captures(line, shadow) do
      {indent, var, op, rhs, tail} ->
        operator = elixir_operator(op, rhs)
        "#{indent}#{var} = #{var} #{operator} (#{rhs})#{tail}"

      nil ->
        line
    end
  end

  defp elixir_operator("+", "[" <> _rest), do: "++"
  defp elixir_operator("+", <<?", _rest::binary>>), do: "<>"
  defp elixir_operator(op, _rhs), do: op

  # `{indent, var, op, rhs, tail}` for a fixable line, or `nil`. The match is
  # located in the shadow and every returned byte is read out of the real line at
  # those offsets — same byte length, same code bytes, so the offsets hold in
  # either. `analyze` and `fix` both come through here, so they cannot disagree.
  #
  # A whole-line comment needs no special case any more: masking blanks it to its
  # last byte, and a run of blanks does not match `[A-Za-z_]\w*`.
  defp captures(line, shadow) do
    case Regex.run(@augmented_pattern, shadow, return: :index, capture: :all_but_first) do
      [indent, var, op, {rhs_start, rhs_len}] ->
        {rhs, tail} = split_expression_from_comment(line, shadow, rhs_start, rhs_len)

        if rhs == "" do
          nil
        else
          {slice(line, indent), slice(line, var), slice(line, op), rhs, tail}
        end

      nil ->
        nil
    end
  end

  defp slice(line, {start, len}), do: binary_part(line, start, len)

  # Splits the captured right-hand side into the expression and whatever trailing
  # comment follows it. With no trailing comment the expression is the capture
  # unchanged and the tail is empty, which is exactly what this rule did before.
  defp split_expression_from_comment(line, shadow, rhs_start, rhs_len) do
    case comment_start(line, shadow) do
      nil ->
        {binary_part(line, rhs_start, rhs_len), ""}

      c when c > rhs_start ->
        code = binary_part(line, rhs_start, c - rhs_start)
        rhs = String.trim_trailing(code)
        kept = byte_size(rhs)
        {rhs, binary_part(line, rhs_start + kept, byte_size(line) - rhs_start - kept)}

      _ ->
        {"", ""}
    end
  end

  # Where a trailing `#` comment begins, or `nil`. A comment is blanked to the
  # end of the line, so it is a run of blanks reaching the line's end — but so is
  # a trailing string literal, and that one is part of the expression. The raw
  # line's byte at the run's first offset is what separates them: `#` opens a
  # comment, a quote or a sigil opens a literal.
  defp comment_start(line, shadow) do
    trimmed_end = byte_size(String.trim_trailing(shadow))
    run_start = blank_run_start(shadow, trimmed_end)

    if run_start < trimmed_end and binary_part(line, run_start, 1) == "#" do
      run_start
    end
  end

  defp blank_run_start(_shadow, 0), do: 0

  defp blank_run_start(shadow, index) do
    case binary_part(shadow, index - 1, 1) do
      <<@blank>> -> blank_run_start(shadow, index - 1)
      _ -> index
    end
  end

  defp build_issue(line_no, op) do
    %Issue{
      rule: :python_augmented_assignment,
      message:
        "Python's `#{op}=` augmented assignment does not exist in Elixir. " <>
          "Use `var = var #{op} (expr)` instead.",
      meta: %{line: line_no}
    }
  end
end
