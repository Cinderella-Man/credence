defmodule Credence.Semantic.PreferMapSizeKernel do
  @moduledoc """
  Replaces deprecated `Map.size/1` with the Kernel built-in `map_size/1`.

  `Map.size/1` was deprecated in Elixir 1.19 in favour of `Kernel.map_size/1`.
  Both return the number of key-value pairs in the map as an integer, so the
  replacement is type-safe.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "Map.size") and
      (String.contains?(msg, "deprecated") or
         String.contains?(msg, "undefined or private"))
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_map_size_kernel,
      message: "Map.size/1 is deprecated; use map_size/1 instead",
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
        String.replace(line_content, "Map.size(", "map_size(", global: false)

      {line_content, _} ->
        line_content
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
