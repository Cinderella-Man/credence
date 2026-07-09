defmodule Credence.Syntax.FixStructFieldAssignmentSyntax do
  @moduledoc """
  Fixes Python/JS-style struct field mutation into Elixir map-update syntax.

  LLMs repeatedly emit `var.field = expr` which fails at compile time with
  "cannot invoke remote function ... inside a match".  The deterministic
  rewrite `var = %{var | field: expr}` fixes the error.

  ## Detected pattern

  A line of the form `<indent><var>.<field> = <expr>` where a dot-access
  target sits on the left-hand side of `=`:

      left.right = node           →  left = %{left | right: node}
      node.left = left_right      →  node = %{node | left: left_right}

  ## Not flagged

  - Comparison operators (`a == b`, `a >= b`, `a =~ b`)
  - Map-update syntax (`%{left | right: node}`)
  - Comments (`# left.right = node`)
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Match: optional leading whitespace, a variable name, `.`, a field name,
  # `=` (not followed by `=` or `~` — rejects `==`, `===`, `=~`), then the
  # right-hand side expression to end of line.
  #
  #   group 1: leading indentation
  #   group 2: variable name (e.g. `left`)
  #   group 3: field name   (e.g. `right`)
  #   group 4: expression   (e.g. `node`)
  @bad_pattern ~r/^(\s*)(\w+)\.(\w+)\s*=(?![=~])\s*(.+)$/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if comment_line?(line) do
        []
      else
        case Regex.run(@bad_pattern, line) do
          [_match, _indent, var, field, _expr] -> [build_issue(line_no, var, field)]
          nil -> []
        end
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if comment_line?(line) do
        line
      else
        Regex.replace(@bad_pattern, line, fn _match, indent, var, field, expr ->
          "#{indent}#{var} = %{#{var} | #{field}: #{String.trim(expr)}}"
        end)
      end
    end)
  end

  defp comment_line?(line), do: Regex.match?(~r/^\s*#/, line)

  defp build_issue(line_no, var, field) do
    %Issue{
      rule: :fix_struct_field_assignment_syntax,
      message:
        "Python/JS-style `#{var}.#{field} = expr` is not valid Elixir. " <>
          "Use `#{var} = %{#{var} | #{field}: expr}` instead.",
      meta: %{line: line_no}
    }
  end
end
