defmodule Credence.Semantic.NoUndefinedGuardEqualityInCase do
  @moduledoc """
  Fixes `case` clauses where an LLM binds a variable in the pattern and
  immediately checks equality with an atom in the guard instead of using
  the atom directly as the pattern.

  LLMs commonly write:

      case :ets.info(table) do
        undefined when undefined == :undefined -> :no_table
        _ -> :ok
      end

  When the idiomatic Elixir is:

      case :ets.info(table) do
        :undefined -> :no_table
        _ -> :ok
      end

  The source that triggers this rule typically also contains the
  `:ets:info` colon-syntax error (`"syntax error before: info"`).
  The fix replaces the redundant bound-variable guard equality with a
  literal pattern match.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_msg "syntax error before: info"
  @guard_regex ~r/(\w+)\s+when\s+\1\s*==\s*:(\w+)/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_msg)
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_undefined_guard_equality_in_case,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    Regex.replace(@guard_regex, source, ":\\2")
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
