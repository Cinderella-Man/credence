defmodule Credence.Semantic.PreferTlOverEnumTail do
  @moduledoc """
  Fixes compiler diagnostics about undefined `Enum.tail/1`.

  LLMs commonly hallucinate `Enum.tail/1` (a mix of Erlang's `tl/1` and
  Haskell's `tail`) but this function does not exist in Elixir. The
  idiomatic equivalent is `tl/1` (from `Kernel`). This rule matches the
  compiler warning and rewrites `Enum.tail` to `tl`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) when is_binary(msg) do
    String.contains?(msg, "Enum.tail") and
      String.contains?(msg, "is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(diagnostic) do
    %Issue{
      rule: :prefer_tl_over_enum_tail,
      message: "Enum.tail/1 does not exist; use tl/1 instead",
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
        String.replace(line_content, "Enum.tail(", "tl(", global: true)

      {line_content, _} ->
        line_content
    end)
  end

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
end
