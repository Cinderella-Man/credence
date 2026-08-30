defmodule Credence.Semantic.NoBareDocAttribute do
  @moduledoc """
  Removes bare `@doc` attributes (no arguments) before `def` declarations.

  LLMs sometimes generate `@doc` with no arguments before a `def`, which
  reads the unset doc attribute as `nil` — a no-op that triggers the compiler
  diagnostic "module attribute @doc in code block has no effect".

  The fix strips the bare `@doc` line, which is safe because reading the unset
  attribute has no effect.

  ## Bad

      defmodule SolutionNBDA do
        @doc
        def calculate_total_cost(price) do
          price * 1.1
        end
      end

  ## Good

      defmodule SolutionNBDA do
        def calculate_total_cost(price) do
          price * 1.1
        end
      end
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
  def fix(source, diagnostic) do
    target = line(diagnostic)
    lines = String.split(source, "\n")

    # Remove ONLY the line the diagnostic points at, and only when that line
    # is genuinely a bare `@doc` (the warning's actual cause). Targeting the
    # diagnostic line — rather than rejecting every `^\s*@doc\s*$` line in the
    # file — keeps `@doc` text that legitimately appears inside an unrelated
    # docstring/heredoc untouched. The phase applies diagnostics bottom-up, so
    # removing a lower line never shifts an earlier diagnostic's line index.
    case Enum.at(lines, target - 1) do
      nil ->
        source

      line ->
        if bare_doc_line?(line) do
          lines |> List.delete_at(target - 1) |> Enum.join("\n")
        else
          source
        end
    end
  end

  # Matches a line that is ONLY `@doc` with no arguments (possibly with
  # surrounding whitespace or a comment). Does NOT match `@doc false`, `@doc "…"`,
  # `@doc """`, etc. — those carry real arguments.
  defp bare_doc_line?(line) do
    String.match?(line, ~r/^\s*@doc\s*(?:#.*)?$/)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
