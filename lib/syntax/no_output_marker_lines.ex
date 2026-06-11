defmodule Credence.Syntax.NoOutputMarkerLines do
  @moduledoc """
  Detects and removes LLM output-marker lines like `---MODULE---`,
  `---TEST---`, or `---END---`.

  LLMs sometimes emit delimiter lines that belong to the surrounding
  prompt scaffolding (e.g. "wrap your answer between ---MODULE--- and
  ---END---") directly into the generated source. These lines cause an
  unfixable `syntax error before: '---'` at line 1 because `---` is not
  valid Elixir syntax.

  This rule strips every line whose entire content matches `^---[A-Z_]+---$`
  (before Sourceror parsing), rescuing the code deterministically.
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  @marker_pattern ~r/^---[A-Z_]+---$/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if String.match?(line, @marker_pattern) do
        [%Issue{rule: :no_output_marker_lines, message: "Output marker line `#{String.trim(line)}` will cause a syntax error.", meta: %{line: line_no}}]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.reject(fn line -> String.match?(line, @marker_pattern) end)
    |> Enum.join("\n")
  end
end
