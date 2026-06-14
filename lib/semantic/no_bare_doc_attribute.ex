defmodule Credence.Semantic.NoBareDocAttribute do
  @moduledoc """
  Removes bare `@doc` attributes (no arguments) before `def` declarations.

  LLMs sometimes generate `@doc` with no arguments before a `def`, which
  assigns `nil` to the doc attribute — a no-op that triggers the compiler
  diagnostic "module attribute @doc in code block has no effect".

  The fix strips the bare `@doc` line, which is safe since it assigns `nil`
  (meaningless before a `def`).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "module attribute @doc in code block has no effect")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_bare_doc_attribute,
      message: "Removing bare @doc attribute (no arguments, no effect)",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    source
    |> String.split("\n")
    |> Enum.reject(&bare_doc_line?/1)
    |> Enum.join("\n")
  end

  # Matches a line that is ONLY `@doc` with no arguments (possibly with
  # surrounding whitespace).  Does NOT match `@doc false`, `@doc "…"`,
  # `@doc """`, etc. — those carry real arguments.
  defp bare_doc_line?(line) do
    String.match?(line, ~r/^\s*@doc\s*$/)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
