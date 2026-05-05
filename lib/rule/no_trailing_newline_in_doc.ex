defmodule Credence.Rule.NoTrailingNewlineInDoc do
  @moduledoc """
  Detects `@doc`, `@moduledoc`, and `@typedoc` strings that contain a
  trailing `\\n` escape sequence.

  LLMs frequently generate documentation strings with a trailing `\\n`
  because Python docstrings use trailing newlines. In Elixir, the closing
  `"` or `\"\"\"` handles line termination — the `\\n` produces an
  unnecessary blank line in the rendered documentation.

  ## Bad

      @doc "Finds the missing number in a list.\\n"

      @moduledoc "A module for palindrome checking.\\n"

  ## Good

      @doc "Finds the missing number in a list."

      @moduledoc "A module for palindrome checking."

  ## Auto-fix

  Strips trailing `\\n` escape sequences from single-line doc strings.
  Heredoc-style docs (`\"\"\"...\"\"\"`) are not modified.
  """

  use Credence.Rule
  alias Credence.Issue

  @doc_attrs [:doc, :moduledoc, :typedoc]

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:@, meta, [{attr, _, [value]}]} = node, acc
        when attr in @doc_attrs and is_binary(value) ->
          if trailing_newline_only?(value) do
            {node, [build_issue(meta, attr) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> String.split("\n")
    |> Enum.map(fn line ->
      if doc_line_with_trailing_newline?(line) do
        strip_trailing_newline(line)
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  # A string has the pattern if it ends with \n (actual newline character)
  # but has no other internal newlines. This distinguishes single-line
  # @doc "text\n" from heredoc @doc """\ntext\n""" which typically has
  # multi-line content.
  defp trailing_newline_only?(value) do
    String.ends_with?(value, "\n") and
      not String.contains?(String.trim_trailing(value, "\n"), "\n")
  end

  # Checks if a source line is a single-line @doc/@moduledoc/@typedoc string
  # that ends with a literal \n before the closing quote.
  defp doc_line_with_trailing_newline?(line) do
    trimmed = String.trim(line)

    starts_with_doc_string?(trimmed) and
      Regex.match?(~r/(\\n)+"\s*$/, line) and
      not has_internal_escaped_newlines?(line)
  end

  defp starts_with_doc_string?(trimmed) do
    String.starts_with?(trimmed, "@doc \"") or
      String.starts_with?(trimmed, "@moduledoc \"") or
      String.starts_with?(trimmed, "@typedoc \"")
  end

  # After stripping the trailing \n sequences, check if any literal \n
  # remains — if so, the string has internal newlines (multi-line content)
  # and should not be auto-fixed.
  defp has_internal_escaped_newlines?(line) do
    stripped = Regex.replace(~r/(\\n)+"\s*$/, line, "\"")
    String.contains?(stripped, "\\n")
  end

  # Strips literal \n (the two source characters backslash + n) before the
  # closing double-quote at end of line. Only matches single-line string
  # syntax — heredocs won't match this pattern.
  defp strip_trailing_newline(line) do
    Regex.replace(~r/(\\n)+"\s*$/, line, "\"")
  end

  defp build_issue(meta, attr) do
    %Issue{
      rule: :no_trailing_newline_in_doc,
      message: """
      `@#{attr}` string has a trailing `\\n` that produces an unnecessary \
      newline at the end of the documentation. Remove it.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
