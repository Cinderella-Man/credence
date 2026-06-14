defmodule Credence.Semantic.PreferEnumJoin do
  @moduledoc """
  Fixes compiler diagnostics about undefined `String.join/2`.

  LLMs frequently generate `String.join(list, separator)` but this
  function does not exist in Elixir. The idiomatic equivalent is
  `Enum.join/2`. This rule matches the compiler warning and rewrites
  `String.join` to `Enum.join`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "String.join") and
      String.contains?(msg, "is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_enum_join,
      message: "String.join/2 does not exist; use Enum.join/2 instead",
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
        String.replace(line_content, "String.join", "Enum.join", global: true)

      {line_content, _} ->
        line_content
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
