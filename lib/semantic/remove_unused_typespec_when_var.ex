defmodule Credence.Semantic.RemoveUnusedTypespecWhenVar do
  @moduledoc """
  Fixes compiler errors caused by unused type variables in @spec clauses.

  When an LLM generates a typespec with a `when` clause that defines a type
  variable (e.g., `when var_ok: true`) but that variable is only referenced
  once (in the `when` clause itself), the Elixir compiler rejects it:

      type variable var_ok is used only once. Type variables in typespecs
      must be referenced at least twice, otherwise it is equivalent to term()

  The fix removes the `when` clause entirely, leaving the spec without it:

      # Before (compiler error)
      @spec foo(integer) :: integer when var_ok: true

      # After (compiles cleanly)
      @spec foo(integer) :: integer
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "type variable") and
      String.contains?(msg, "used only once")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :remove_unused_typespec_when_var,
      message: "Unused type variable in @spec — removing when clause",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, %{position: position}) do
    line_no = line(%{position: position})

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {line_content, ^line_no} ->
        # Remove the `when ...` clause from the @spec line
        remove_when_clause(line_content)

      {line_content, _} ->
        line_content
    end)
  end

  defp remove_when_clause(line_content) do
    # Match @spec ... when <clause> and remove the when part
    # The when clause starts after the return type
    case Regex.run(~r/^(\s*@spec\s+.+?::\s+.+?)\s+when\s+.+$/, line_content) do
      [_, spec_without_when] -> spec_without_when
      _ -> line_content
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
