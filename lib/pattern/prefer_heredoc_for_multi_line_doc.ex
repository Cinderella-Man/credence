defmodule Credence.Pattern.PreferHeredocForMultiLineDoc do
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

  use Credence.Pattern.Rule
  alias Credence.Issue

  @doc_attrs [:doc, :moduledoc, :typedoc]

  @impl true
  def priority, do: 501

  # Sourceror records the string delimiter (`"""` vs `"`) in the
  # `:__block__` metadata's `:delimiter` key. The check uses that to
  # tell heredocs apart from escape-string docs purely from the AST.

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Sourceror shape: string wrapped in :__block__ with :delimiter meta.
        {:@, meta, [{attr, _, [{:__block__, str_meta, [value]}]}]} = node, acc
        when attr in @doc_attrs and is_binary(value) ->
          already_heredoc = Keyword.get(str_meta, :delimiter) == ~s(""")

          if not already_heredoc and (raw_multi_line?(value) or real_multi_line?(value)) do
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
  def fix_patches(ast, opts) do
    # Sourceror's AST preserves both shapes of multi-line doc strings:
    # `@doc "a\\nb"` keeps the literal `\\n` in the string value, while
    # `@doc """\na\nb\n"""` carries a `:delimiter` of `~s(""")` in the
    # block metadata. `fix_doc_node/1` handles both via `raw_multi_line?`
    # and `real_multi_line?`. The `:delimiter` check skips already-heredoc
    # strings — re-processing one through `Sourceror.to_string` corrupts
    # indentation.
    #
    # We render the whole fixed AST rather than emitting per-node patches
    # because `Sourceror.patch_string` swallows the trailing newline after
    # a patch range when the range spans multiple source lines (real
    # newlines case).  A whole-source patch avoids this edge case.
    source = Keyword.get(opts, :source, "")
    transformed = Macro.postwalk(ast, &fix_doc_node/1)

    if transformed == ast do
      []
    else
      new_source =
        transformed
        |> Sourceror.to_string()
        |> ensure_trailing_newline()

      if new_source == source do
        []
      else
        lines = String.split(source, "\n")
        end_line = max(length(lines), 1)
        end_col = (lines |> List.last() |> byte_size()) + 1

        [
          %{
            range: %{start: [line: 1, column: 1], end: [line: end_line, column: end_col]},
            change: new_source
          }
        ]
      end
    end
  end

  defp fix_doc_node({:@, meta, [{attr, attr_meta, [{:__block__, str_meta, [value]}]}]} = node)
       when attr in @doc_attrs and is_binary(value) do
    # Already a heredoc — leave it alone.  Sourceror records the delimiter
    # in the string block's metadata; re-processing a heredoc through
    # Sourceror.to_string corrupts indentation and destroys the file.
    if Keyword.get(str_meta, :delimiter) == ~s(""") do
      node
    else
      cond do
        raw_multi_line?(value) ->
          # Sourceror needs the value to end with `\n` so the closing
          # `"""` renders on its own line — without it the closing
          # delimiter ends up glued to the last content line.
          content = unescape_value(value) |> ensure_trailing_newline()
          new_str_meta = Keyword.put(str_meta, :delimiter, ~s("""))
          {:@, meta, [{attr, attr_meta, [{:__block__, new_str_meta, [content]}]}]}

        real_multi_line?(value) ->
          content = ensure_trailing_newline(value)
          new_str_meta = Keyword.put(str_meta, :delimiter, ~s("""))
          {:@, meta, [{attr, attr_meta, [{:__block__, new_str_meta, [content]}]}]}

        true ->
          node
      end
    end
  end

  defp fix_doc_node(node), do: node

  defp ensure_trailing_newline(s) do
    if String.ends_with?(s, "\n"), do: s, else: s <> "\n"
  end

  defp raw_multi_line?(value) do
    trimmed = String.trim_trailing(value, "\\n")
    String.contains?(trimmed, "\\n")
  end

  defp real_multi_line?(value) do
    trimmed = String.trim_trailing(value, "\n")
    String.contains?(trimmed, "\n")
  end

  defp unescape_value(value) do
    value
    |> String.replace("\\\\", "\x00BACKSLASH\x00")
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\"", "\"")
    |> String.replace("\x00BACKSLASH\x00", "\\")
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
