defmodule Credence.Semantic.NoDocSpecOutsideModule do
  @moduledoc """
  Matches compiler diagnostics when @doc or @spec attributes are used outside
  a defmodule wrapper, and fixes by wrapping the source in
  defmodule Solution do ... end.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(diagnostic) do
    message = diagnostic.message
    (String.contains?(message, "@doc") or String.contains?(message, "@spec")) and
      String.contains?(message, "outside module")
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_doc_spec_outside_module,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    indented =
      source
      |> String.trim_trailing("\n")
      |> String.split("\n")
      |> Enum.map(fn
        "" -> ""
        line -> "  " <> line
      end)
      |> Enum.join("\n")

    "defmodule Solution do\n#{indented}\nend\n"
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end