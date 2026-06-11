defmodule Credence.Semantic.PreferEnumSliceOverListSlice do
  @moduledoc """
  Fixes compiler diagnostics about undefined `List.slice/3`.

  LLMs frequently generate `List.slice(list, start, count)` but this
  3-arity version does not exist in Elixir. The idiomatic equivalent is
  `Enum.slice/3`. This rule matches the compiler warning and rewrites
  `List.slice` to `Enum.slice`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "List.slice/3 is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_enum_slice_over_list_slice,
      message: "List.slice/3 does not exist; use Enum.slice/3 instead",
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
        String.replace(line_content, "List.slice", "Enum.slice", global: false)

      {line_content, _} ->
        line_content
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
