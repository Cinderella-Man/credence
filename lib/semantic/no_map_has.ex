defmodule Credence.Semantic.NoMapHas do
  @moduledoc """
  Fixes the undefined-function error caused by `Map.has?/2`.

  `Map.has?/2` is a common typo for `Map.has_key?/2`; this rule
  deterministically renames the call to the correct function.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @match_target "Map.has?/"

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, @match_target) and
      (String.contains?(msg, "undefined or private") or
         String.contains?(msg, "undefined function"))
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :no_map_has,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    line_no = line(diagnostic)

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {l, ^line_no} -> String.replace(l, "Map.has?", "Map.has_key?", global: false)
      {l, _} -> l
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
