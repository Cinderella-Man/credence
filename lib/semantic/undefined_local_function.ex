defmodule Credence.Semantic.UndefinedLocalFunction do
  @moduledoc """
  Fixes compiler errors about undefined local functions with known replacements.

  LLMs sometimes hallucinate local functions that don't exist in Elixir,
  often translating idioms from other languages. This rule maintains a
  mapping of known corrections.

  ## Example

      # Error: undefined function infinity/0
      Enum.reduce(nums, {-infinity(), -infinity()}, fn ...)

      # Fixed:
      Enum.reduce(nums, {-:math.inf(), -:math.inf()}, fn ...)
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  # Map of {function_name, arity} → replacement text
  @replacements %{
    {"infinity", 0} => ":math.inf()"
  }

  @impl true
  def match?(%{severity: :error, message: msg}) do
    case parse_local_ref(msg) do
      nil -> false
      ref -> Map.has_key?(@replacements, ref)
    end
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :undefined_local_function,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    line_no = extract_line(position)

    case parse_local_ref(msg) do
      {name, 0} = key ->
        case Map.get(@replacements, key) do
          nil -> source
          replacement -> replace_on_line(source, line_no, "#{name}()", replacement)
        end

      _ ->
        source
    end
  end

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp parse_local_ref(msg) do
    case Regex.run(~r/undefined function (\w+)\/(\d+)/, msg) do
      [_, name, arity] -> {name, String.to_integer(arity)}
      _ -> nil
    end
  end

  defp replace_on_line(source, line_no, old, new) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> String.replace(line, old, new)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end
end
