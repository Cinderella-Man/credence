defmodule Credence.Semantic.UndefinedStringAlphanumeric do
  @moduledoc """
  Fixes the common LLM hallucination where `String.alphanumeric?/1` is called
  as if it were a real Elixir standard library function. It is not.

  LLMs translating Python's `str.isalnum()` frequently produce:

      Enum.filter(&String.alphanumeric?/1)

  This compiles but warns `String.alphanumeric?/1 is undefined or private`,
  which becomes a hard error under `--warnings-as-errors`.

  The fix replaces:
  - `&String.alphanumeric?/1` → `fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end`
  - `String.alphanumeric?(expr)` → `String.match?(expr, ~r/^[a-zA-Z0-9]$/)`

  ## Bad

      defmodule AlphanumCheckInteg1 do
        def clean(s) do
          s |> String.graphemes() |> Enum.filter(&String.alphanumeric?/1)
        end
      end

  ## Good

      defmodule AlphanumCheckInteg1 do
        def clean(s) do
          s |> String.graphemes() |> Enum.filter(fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end)
        end
      end
  """
  use Credence.Semantic.Rule
  alias Credence.Issue

  @replacement "fn char -> String.match?(char, ~r/^[a-zA-Z0-9]$/) end"

  @impl true
  def match?(%{severity: :warning, message: msg}) do
    String.contains?(msg, "String.alphanumeric?") and
      String.contains?(msg, "is undefined or private")
  end

  def match?(_), do: false

  @impl true
  def to_issue(%{message: msg, position: position}) do
    %Issue{
      rule: :undefined_string_alphanumeric,
      message: msg,
      meta: %{line: extract_line(position)}
    }
  end

  @impl true
  def fix(source, %{position: position}) do
    line_no = extract_line(position)

    if line_no do
      fix_line(source, line_no)
    else
      source
    end
  end

  defp extract_line({line, _col}) when is_integer(line), do: line
  defp extract_line(line) when is_integer(line), do: line
  defp extract_line(_), do: nil

  defp fix_line(source, line_no) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn
      {line, ^line_no} -> replace_alphanumeric(line)
      {line, _} -> line
    end)
  end

  defp replace_alphanumeric(line) do
    line
    # Capture form: &String.alphanumeric?/1
    |> String.replace("&String.alphanumeric?/1", @replacement)
    # Direct call form: String.alphanumeric?(expr)
    |> then(fn l ->
      Regex.replace(~r/String\.alphanumeric\?\(([^)]+)\)/, l, fn _, arg ->
        "String.match?(#{String.trim(arg)}, ~r/^[a-zA-Z0-9]$/)"
      end)
    end)
  end
end
