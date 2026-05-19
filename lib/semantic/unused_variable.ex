defmodule Credence.Semantic.UnusedVariable do
  @moduledoc """
  Fixes compiler warnings about unused variables by adding `_` prefix.

  LLMs often generate destructuring patterns where not all bound variables
  are used, causing `--warnings-as-errors` to fail compilation.

  ## Example

      # Warning: variable "current_sum" is unused
      {current_sum, max_sum} = Enum.reduce(...)

      # Fixed:
      {_current_sum, max_sum} = Enum.reduce(...)
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  @impl true
  def match?(%{severity: :warning, message: msg}) do
    String.match?(msg, ~r/variable ".*" is unused/)
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :unused_variable,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    line_no = extract_line(position)
    var_name = extract_variable_name(msg)

    if line_no && var_name && not String.starts_with?(var_name, "_") do
      replace_on_line(source, line_no, var_name, "_#{var_name}")
    else
      source
    end
  end

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp extract_variable_name(msg) do
    case Regex.run(~r/variable "([^"]+)" is unused/, msg) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp replace_on_line(source, line_no, old, new) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {line, ^line_no} -> String.replace(line, old, new, global: false)
      {line, _} -> line
    end)
  end
end
