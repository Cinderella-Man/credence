defmodule Credence.Semantic.NoNonNegatedInteger do
  @moduledoc """
  Fixes compiler errors about the undefined type `non_negated_integer/0`.

  LLMs commonly produce `non_negated_integer()` in typespecs when they mean
  `non_neg_integer()`.  The Elixir compiler emits:

      type non_negated_integer/0 undefined (no such type in Module)

  The fix is a safe textual substitution — `non_negated_integer` →
  `non_neg_integer` — with no behaviour change (both types describe the
  same set of values).
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "non_negated_integer") and
      String.contains?(msg, "undefined")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_non_negated_integer,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    String.replace(source, "non_negated_integer", "non_neg_integer")
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
