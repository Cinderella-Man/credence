defmodule Credence.Rule.PreferHeredocForMultiLineDoc do
  @moduledoc """
  Detects `@doc`, `@moduledoc`, and `@typedoc` strings that contain
  escaped newlines (`\\n`) and should use heredoc syntax instead.

  LLMs generate documentation as single-line strings with `\\n` escapes
  because that's how Python docstrings work. In Elixir, multi-line
  documentation should use the heredoc (`\"\"\"`) syntax for readability.

  ## Bad

      @doc "Finds the second largest number in a list.\\nThe list must have at least two distinct values.\\n"

  ## Good

      @doc \"\"\"
      Finds the second largest number in a list.
      The list must have at least two distinct values.
      \"\"\"

  ## Auto-fix

  Converts single-line `@doc`/`@moduledoc`/`@typedoc` strings containing
  `\\n` escapes into heredoc format. The fixer preserves indentation and
  strips unnecessary trailing `\\n` (since heredocs naturally end with a
  newline). Strings containing `\\\"\\\"\\\"` are left unchanged.
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
          if multi_line_in_single_string?(value) do
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
    |> fix_lines([])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  # The string value (in AST) has at least one internal \n, meaning it
  # contains multi-line content. We require at least one \n that is not
  # merely trailing — i.e., the content before the trailing newlines
  # contains a newline.
  defp multi_line_in_single_string?(value) do
    trimmed = String.trim_trailing(value, "\n")
    String.contains?(trimmed, "\n")
  end

  # ── Fix: line-by-line processing ────────────────────────────────

  defp fix_lines([], acc), do: acc

  defp fix_lines([line | rest], acc) do
    case try_extract_doc_string(line) do
      {:ok, attr, indent, content_raw} ->
        if safe_to_convert?(content_raw) do
          heredoc_lines = build_heredoc(attr, indent, content_raw)
          fix_lines(rest, Enum.reverse(heredoc_lines) ++ acc)
        else
          fix_lines(rest, [line | acc])
        end

      :skip ->
        fix_lines(rest, [line | acc])
    end
  end

  # Try to extract a single-line @doc/@moduledoc/@typedoc "..." with internal \n.
  # Returns {:ok, attr, indent, raw_content} or :skip.
  # Skips strings that only have trailing \n (that's NoTrailingNewlineInDoc's job).
  defp try_extract_doc_string(line) do
    case Regex.run(
           ~r/^(\s*)@(doc|moduledoc|typedoc)\s+"(.*)"(\s*)$/,
           line
         ) do
      [_full, indent, attr, content, _trailing] ->
        if has_internal_escaped_newlines?(content) do
          {:ok, attr, indent, content}
        else
          :skip
        end

      _ ->
        :skip
    end
  end

  # After stripping trailing \n sequences, check if any \n remains.
  # If yes, the string has internal newlines → multi-line content.
  defp has_internal_escaped_newlines?(content) do
    stripped = Regex.replace(~r/(\\n)+$/, content, "")
    String.contains?(stripped, "\\n")
  end

  # Don't convert if the content contains triple quotes (would break heredoc)
  defp safe_to_convert?(content_raw) do
    not String.contains?(content_raw, ~S("""))
  end

  defp build_heredoc(attr, indent, content_raw) do
    # Unescape the content:
    # - \n → actual newlines
    # - \" → "
    # - \\ → \
    # - \t → tab
    content =
      content_raw
      |> String.replace("\\n", "\n")
      |> String.replace("\\\"", "\"")
      |> String.replace("\\\\", "\\")
      |> String.replace("\\t", "\t")

    # Strip trailing newlines (heredoc closing """ adds one naturally)
    content = String.trim_trailing(content, "\n")

    # Split into lines and indent each
    doc_lines =
      content
      |> String.split("\n")
      |> Enum.map(fn doc_line ->
        if doc_line == "" do
          ""
        else
          "#{indent}#{doc_line}"
        end
      end)

    # Build: @attr """\n<content>\n"""
    opening = "#{indent}@#{attr} \"\"\""
    closing = "#{indent}\"\"\""

    [opening | doc_lines] ++ [closing]
  end

  defp build_issue(meta, attr) do
    %Issue{
      rule: :prefer_heredoc_for_multi_line_doc,
      message: """
      `@#{attr}` contains multi-line content using `\\n` escape sequences. \
      Use heredoc (`\"\"\"`) syntax instead for readability.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
