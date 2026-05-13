defmodule Credence.Semantic.UndefinedLocalFunction do
  @moduledoc """
  Fixes compiler errors about undefined local functions with known replacements.

  LLMs sometimes hallucinate local functions that don't exist in Elixir,
  often translating idioms from other languages. This rule maintains a
  mapping of known corrections.

  ## Literal example (arity-0 call → replacement text)

      # Error: undefined function infinity/0
      Enum.reduce(nums, {-infinity(), -infinity()}, fn ...)

      # Fixed:
      Enum.reduce(nums, {-:math.inf(), -:math.inf()}, fn ...)

  ## Rename example (bare call → qualified call)

      # Error: undefined function max/1
      max([option1, option2])

      # Fixed:
      Enum.max([option1, option2])
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  # ── Replacement table ──────────────────────────────────────────
  #
  #   {:literal, text}         — replace name() with text (arity-0 only)
  #   {:rename, mod, fun}      — replace name( with mod.fun( (any arity)

  @replacements %{
    # Python float('inf') → bare infinity() call
    {"infinity", 0} => {:literal, ":math.inf()"},

    # Python max(list) → bare max(list) — Elixir's Kernel.max/2 takes 2 args, not a list
    {"max", 1} => {:rename, "Enum", "max"}
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
      {name, _arity} = key ->
        case Map.get(@replacements, key) do
          nil ->
            source

          {:literal, replacement} ->
            replace_on_line(source, line_no, "#{name}()", replacement)

          {:rename, mod, fun} ->
            replace_on_line(source, line_no, "#{name}(", "#{mod}.#{fun}(")
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
