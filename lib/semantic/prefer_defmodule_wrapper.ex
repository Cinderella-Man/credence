defmodule Credence.Semantic.PreferDefmoduleWrapper do
  @moduledoc """
  Matches the "cannot invoke @/1 outside module" diagnostic emitted when
  module attributes (`@moduledoc`, `@doc`, `@spec`) appear at file scope
  without a `defmodule` wrapper, and wraps the entire source in
  `defmodule Solution do ... end`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(diagnostic) do
    case diagnostic do
      %{message: message} ->
        String.contains?(message, "cannot invoke @/1 outside module")

      _ ->
        false
    end
  end

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_defmodule_wrapper,
      message: "Module attributes used without a defmodule wrapper",
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, _diagnostic) do
    trimmed = String.trim_leading(source)

    if String.starts_with?(trimmed, "defmodule ") do
      source
    else
      wrap_in_defmodule(source)
    end
  end

  defp wrap_in_defmodule(source) do
    lines = source |> String.trim_trailing("\n") |> String.split("\n")

    indented =
      lines
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