defmodule Credence.Syntax.FixPythonAugmentedAssignment do
  @moduledoc """
  Replaces Python's augmented assignment operators (`+=`, `-=`, `*=`, `/=`)
  with Elixir's rebinding syntax.

  LLMs translating from Python carry over augmented assignment operators.
  In Elixir, `+=` and friends are not valid — variables are rebound with `=`,
  so `x += expr` must become `x = x + expr`.

  This is a Syntax rule because `x += y` won't parse in Elixir.

  ## Detected patterns

      count += 1                x -= delta
      total *= factor           value /= divisor

  Any `identifier op= expression` where `op` is `+`, `-`, `*`, or `/`.

  ## Not flagged

  Legitimate Elixir code is not affected — `+=` and friends never appear
  as valid Elixir tokens. Comment lines are skipped.

  ## Bad

      count += Map.get(freq, key, 0)
      total *= factor

  ## Good

      count = count + Map.get(freq, key, 0)
      total = total * factor
  """

  use Credence.Syntax.Rule
  alias Credence.Issue

  @augmented_ops ["+=", "-=", "*=", "/="]

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case find_augmented_op(line) do
        {:ok, op} -> [build_issue(line_no, op)]
        :error -> []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if comment_line?(line), do: line, else: fix_line(line)
    end)
  end

  defp find_augmented_op(line) do
    if comment_line?(line) do
      :error
    else
      Enum.find_value(@augmented_ops, :error, fn op ->
        if Regex.match?(build_pattern(op), line), do: {:ok, op}, else: nil
      end)
    end
  end

  defp fix_line(line) do
    Enum.reduce(@augmented_ops, line, fn op, acc ->
      Regex.replace(build_pattern(op), acc, fn _match, var ->
        operator = String.trim_trailing(op, "=")
        "#{var} = #{var} #{operator} "
      end)
    end)
  end

  # `(\w+)\s*\+=\s*` matches `variable_name += ` with optional whitespace.
  defp build_pattern(op) do
    escaped = Regex.escape(op)
    Regex.compile!("(\\b\\w+)\\s*#{escaped}\\s*")
  end

  defp comment_line?(line), do: Regex.match?(~r/^\s*#/, line)

  defp build_issue(line_no, op) do
    operator = String.trim_trailing(op, "=")

    %Issue{
      rule: :python_augmented_assignment,
      message:
        "Python's `#{op}` augmented assignment does not exist in Elixir. " <>
          "Use `var = var #{operator} expr` instead.",
      meta: %{line: line_no}
    }
  end
end
