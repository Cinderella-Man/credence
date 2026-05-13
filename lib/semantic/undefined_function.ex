defmodule Credence.Semantic.UndefinedFunction do
  @moduledoc """
  Fixes compiler warnings about undefined or deprecated functions with known replacements.

  LLMs sometimes use functions that don't exist in the expected module or
  have been deprecated in favour of a replacement. This rule maintains a
  mapping of known corrections.

  ## Rename examples (module.function → module.function)

      # Warning: Enum.last/1 is undefined or private
      list |> Enum.last()
      # Fixed:
      list |> List.last()

      # Warning: Enum.partition/2 is deprecated. Use Enum.split_with/2 instead
      Enum.partition(list, &pred/1)
      # Fixed:
      Enum.split_with(list, &pred/1)

  ## Literal examples (hallucinated call → Elixir literal)

      # Warning: Float.NegInfinity/0 is undefined or private
      validate(root, Float.NegInfinity(), Float.PositiveInfinity())
      # Fixed:
      validate(root, :neg_infinity, :infinity)

      # Warning: Integer.min_value/0 is undefined or private
      @min_bound Integer.min_value()
      # Fixed:
      @min_bound :neg_infinity
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  # ── Replacement table ──────────────────────────────────────────
  #
  #   {:rename, new_mod, new_fun}  — swap Module.function, keep args/parens
  #   {:literal, text}             — replace Module.function() with a literal

  @replacements %{
    # Wrong module for real function
    {"Enum", "last", 1} => {:rename, "List", "last"},
    {"Enum", "last", 0} => {:rename, "List", "last"},
    {"List", "reverse", 1} => {:rename, "Enum", "reverse"},

    # Deprecated
    {"Enum", "partition", 2} => {:rename, "Enum", "split_with"},

    # Hallucinated Float infinity (from Python float('inf') / Java Double.POSITIVE_INFINITY)
    {"Float", "NegInfinity", 0} => {:literal, ":neg_infinity"},
    {"Float", "PositiveInfinity", 0} => {:literal, ":infinity"},
    {"Float", "NegInf", 0} => {:literal, ":neg_infinity"},
    {"Float", "Infinity", 0} => {:literal, ":infinity"},

    # Hallucinated Integer bounds (from Java Integer.MIN_VALUE / MAX_VALUE)
    {"Integer", "min_value", 0} => {:literal, ":neg_infinity"},
    {"Integer", "max_value", 0} => {:literal, ":infinity"},

    # Hallucinated List.pop (from Python list.pop() — get last element)
    {"List", "pop", 1} => {:rename, "List", "last"}
  }

  @impl true
  def match?(%{severity: :warning, message: msg}) do
    (String.contains?(msg, "is undefined or private") or String.contains?(msg, "is deprecated")) and
      parse_function_ref(msg) != nil and
      Map.has_key?(@replacements, parse_function_ref(msg))
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :undefined_function,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{message: msg, position: position}) do
    line_no = extract_line(position)

    case parse_function_ref(msg) do
      {mod, fun, _arity} = key ->
        case Map.get(@replacements, key) do
          {:rename, new_mod, new_fun} ->
            replace_on_line(source, line_no, "#{mod}.#{fun}", "#{new_mod}.#{new_fun}")

          {:literal, text} ->
            replace_on_line(source, line_no, "#{mod}.#{fun}()", text)

          nil ->
            source
        end

      nil ->
        source
    end
  end

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp parse_function_ref(msg) do
    case Regex.run(~r/(\w+)\.(\w+)\/(\d+) is (undefined or private|deprecated)/, msg) do
      [_, mod, fun, arity, _] -> {mod, fun, String.to_integer(arity)}
      _ -> nil
    end
  end

  defp replace_on_line(source, line_no, old, new) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn
      {line, ^line_no} -> String.replace(line, old, new, global: false)
      {line, _} -> line
    end)
    |> Enum.join("\n")
  end
end
