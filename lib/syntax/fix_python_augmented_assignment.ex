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

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case captures(line) do
        [_indent, _var, op, _rhs] -> [build_issue(line_no, op)]
        nil -> []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &fix_line/1)
  end

  defp fix_line(line) do
    case captures(line) do
      [indent, var, op, rhs] -> "#{indent}#{var} = #{var} #{op} (#{rhs})"
      nil -> line
    end
  end

  # Returns `[indent, var, op, rhs]` for a fixable line, or `nil`.
  # Comment lines never match.
  defp captures(line) do
    if comment_line?(line) do
      nil
    else
      case Regex.run(@augmented_pattern, line, capture: :all_but_first) do
        [indent, var, op, rhs] -> [indent, var, op, rhs]
        nil -> nil
      end
    end
  end

  defp comment_line?(line), do: Regex.match?(~r/^\s*#/, line)

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
