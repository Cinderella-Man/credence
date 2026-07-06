defmodule Credence.Semantic.NoEtsInfoBareSize do
  @moduledoc """
  Repairs the common LLM error where `:ets.info(table, size)` is written
  instead of the idiomatic `:ets.info(table, :size)`.

  The bare `size` is interpreted as a variable reference, producing an
  `undefined variable "size"` compile error. The fix atomises the bare
  second argument so the call becomes `:ets.info(table, :size)`.
  """
  use Credence.Semantic.Rule

  alias Credence.Issue

  @ets_info_bare_regex ~r/(:ets\.info\([^)]*,\s*)size\s*\)/

  @impl true
  def match?(%{severity: :error, message: msg}) when is_binary(msg) do
    String.contains?(msg, "undefined variable") and
      String.contains?(msg, "\"size\"")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :no_ets_info_bare_size,
      message: msg,
      meta: %{line: line(position)}
    }
  end

  @impl true
  def fix(source, %{position: position}) do
    case line(position) do
      nil ->
        source

      line_no ->
        source
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn
          {text, ^line_no} -> fix_line(text)
          {text, _} -> text
        end)
    end
  end

  defp fix_line(text) do
    Regex.replace(@ets_info_bare_regex, text, "\\1:size)")
  end

  defp line({line, _col}), do: line
  defp line(line) when is_integer(line), do: line
  defp line(_), do: nil
end
