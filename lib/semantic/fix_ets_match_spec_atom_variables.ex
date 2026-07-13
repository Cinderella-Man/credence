defmodule Credence.Semantic.FixEtsMatchSpecAtomVariables do
  @moduledoc """
  Fixes ETS match spec variables written as atoms instead of charlists.

  LLMs commonly write ETS match spec variables as atoms (`:'$1'`) instead of
  charlists (`~c"$1"`), causing parse errors. The compiler emits:

      error: unexpected token: "$"

  when it encounters the `$` character in an atom literal inside a context
  where it expects a charlist. The fix replaces atom match spec variables
  with charlist sigils:

      :'$1'  →  ~c"$1"
      :'$2'  →  ~c"$2"

  Operator atoms like `:'=<'` are left unchanged — they are not match spec
  variables.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_substring ~s(unexpected token: "$")

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_substring)
  end

  def match?(_), do: false

  @doc false
  def should_report?(_diagnostic, source) do
    String.contains?(source, ":'$")
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_ets_match_spec_atom_variables,
      message:
        "ETS match spec variables written as atoms. " <>
          "Use ~c\"$N\" charlists instead of :'$N' atoms for match spec variables.",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    String.replace(source, ~r/:'\$([\d]+)'/, ~S(~c"$\1"))
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
