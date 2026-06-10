defmodule Credence.Semantic.RequireDefmoduleWrapper do
  @moduledoc """
  Matches Elixir compiler diagnostics about code defined outside a module
  (e.g. @doc, @spec, def at the top level) and wraps the bare source in
  a `defmodule Solution do ... end` block.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: message}) when is_binary(message) do
    String.contains?(message, "outside module")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :require_defmodule_wrapper,
      message: "Top-level code must be wrapped in a defmodule",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    trimmed = String.trim_trailing(source)
    "defmodule Solution do\n" <> trimmed <> "\nend\n"
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end