defmodule Credence.Semantic.FixDeprecatedMapMap do
  @moduledoc """
  Fixes `Map.map/2` deprecation warnings by rewriting to `Map.new/2`.

  `Map.map/2` has been deprecated since Elixir 1.14. LLMs frequently generate
  `Map.map(map, fn {k, v} -> ... end)` which triggers:

      Map.map/2 is deprecated. Use Map.new/2 instead.

  `Map.map(fun, enumerable)` and `Map.new(fun, enumerable)` have the same
  callback arity and return type, so this is a safe 1:1 rewrite.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{message: msg}) when is_binary(msg) do
    String.contains?(msg, "Map.map") and String.contains?(msg, "is deprecated")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :fix_deprecated_map_map,
      message: diagnostic.message,
      meta: %{line: line(diagnostic)}
    }
  end

  @impl true
  def fix(source, diagnostic) do
    line_no = line(diagnostic)

    if line_no do
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn
        {text, ^line_no} -> String.replace(text, "Map.map(", "Map.new(", global: false)
        {text, _} -> text
      end)
    else
      source
    end
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_), do: nil
end
