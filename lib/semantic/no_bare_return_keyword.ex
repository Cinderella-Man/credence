defmodule Credence.Semantic.NoBareReturnKeyword do
  @moduledoc """
  Removes bare `return` keywords from Elixir blocks.

  LLMs (trained on Python) frequently emit `return` as an early-exit statement
  in Elixir blocks. Elixir has no `return` keyword — this compiles to an
  `undefined variable "return"` error because the parser treats it as a
  variable reference. The fix removes the bare `return` line from the block,
  which restores the surrounding control flow to idiomatic Elixir.

  The `context == nil` guard ensures we only match the bare keyword form
  (`{:return, _, nil}`), not a legitimate function call like `return(value)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "undefined variable \"return\""

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_bare_return_keyword,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    target = line(diagnostic)
    lines = String.split(source, "\n")

    case Enum.at(lines, target - 1) do
      nil ->
        source

      text ->
        if bare_return_line?(text) do
          lines |> List.delete_at(target - 1) |> Enum.join("\n")
        else
          source
        end
    end
  end

  # Matches a line that is ONLY `return` with no arguments (possibly with
  # surrounding whitespace). Does NOT match `return value`, `return()`, etc.
  defp bare_return_line?(line) do
    String.match?(line, ~r/^\s*return\s*$/)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
