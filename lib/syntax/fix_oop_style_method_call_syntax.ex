defmodule Credence.Syntax.FixOopStyleMethodCallSyntax do
  @moduledoc """
  Detects and fixes OOP-style method call syntax that won't parse in Elixir.

  LLMs produce `variable.method?(variable)` — the variable is passed
  redundantly as the first argument to a predicate method called via dot syntax.
  Elixir does not parse this: `bucket.finalized?(bucket)` is a compile-blocking
  syntax error.

  The fix removes the redundant argument, converting the call to field/predicate
  access syntax: `bucket.finalized?(bucket)` → `bucket.finalized?`.

  ## Bad (won't compile)

      bucket.finalized?(bucket)
      state.active?(state)

  ## Good

      bucket.finalized?
      state.active?
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  # Match: variable.method_name?(same_variable)
  #   group 1: variable name (e.g. `bucket`)
  #   group 2: method name with ? suffix (e.g. `finalized?`)
  #   group 3: same variable name (backreference)
  #
  # The \b at the start ensures we don't match inside a longer identifier.
  # The (?![\w.]) at the end ensures we don't match a prefix of a longer call.
  @bad_pattern ~r/\b(\w+)\.(\w+\?)\(\1\)(?![\w.])/

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
          [_match, var, method] ->
            [build_issue(line_no, var, method)]

          nil ->
            []
        end
      end
    end)
  end

  @impl true
  def fix(source) do
    Regex.replace(@bad_pattern, source, fn _match, var, method ->
      "#{var}.#{method}"
    end)
  end

  defp comment_line?(line), do: Regex.match?(~r/^\s*#/, line)

  defp build_issue(line_no, var, method) do
    %Issue{
      rule: :fix_oop_style_method_call_syntax,
      message:
        "OOP-style `#{var}.#{method}(#{var})` is not valid Elixir. " <>
          "Use `#{var}.#{method}` (field/predicate access) instead.",
      meta: %{line: line_no}
    }
  end
end
