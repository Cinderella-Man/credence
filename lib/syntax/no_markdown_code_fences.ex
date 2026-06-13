defmodule Credence.Syntax.NoMarkdownCodeFences do
  @moduledoc """
  Detects and removes markdown code-fence lines from generated Elixir source.

  LLMs frequently wrap generated Elixir in markdown code-fence lines
  (U+0060×3, optionally with a language tag like `elixir`). These are
  invalid Elixir tokens causing parse errors that no existing rule targets.

  This rule strips every standalone triple-backtick line — optionally
  preceded by whitespace and followed by a language tag — before parsing,
  rescuing the code deterministically. (A line that is nothing but
  triple-backticks with an optional language tag is never valid Elixir,
  so allowing surrounding whitespace introduces no false positives.)

  ## Bad (won't parse)

      ```elixir
      defmodule Solution do
        def hello, do: :world
      end
      ```

  ## Good

      defmodule Solution do
        def hello, do: :world
      end
  """
  use Credence.Syntax.Rule

  alias Credence.Issue

  # Matches a standalone markdown code-fence line: optional leading/trailing
  # whitespace, exactly three backticks, optionally followed by a language tag
  # (word characters), then optional trailing whitespace.
  @fence_pattern ~r/^\s*```[\w]*\s*$/

  @impl true
  def analyze(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if String.match?(line, @fence_pattern) do
        [
          %Issue{
            rule: :no_markdown_code_fences,
            message: "Markdown code-fence line will cause a syntax error.",
            meta: %{line: line_no}
          }
        ]
      else
        []
      end
    end)
  end

  @impl true
  def fix(source) do
    source
    |> String.split("\n")
    |> Enum.reject(fn line -> String.match?(line, @fence_pattern) end)
    |> Enum.join("\n")
  end
end
