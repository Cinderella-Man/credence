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
  newline). A doc whose value contains an escaped triple quote is converted
  like any other and the quote is re-escaped inside the heredoc — executed:
  the output parses and the doc value is byte-identical. (This paragraph used
  to claim such strings were "left unchanged", which is not what the code
  does; there is no such guard in `fix_doc_node/1` and none is needed.)

  ## Scope

  Only `\\n`-escaped strings (the form LLMs emit) are converted, via a
  per-node patch over just the doc attribute. A doc string that *already*
  spans multiple source lines (a real-newline regular string) is left
  untouched: its multi-line range trips a `Sourceror.patch_string` edge that
  swallows the following newline, and the only safe alternative — rendering
  the whole file — would reformat unrelated, not-yet-formatted code.
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

          if not already_heredoc and raw_multi_line?(value) do
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
  def fix_patches(ast, _opts) do
    # Emit one patch per converted `@doc`/`@moduledoc`/`@typedoc` node, scoped
    # to that node's range. A previous version rendered the whole fixed AST
    # through `Sourceror.to_string` and patched the entire file, which
    # reformatted unrelated code (`x+1` → `x + 1`, `z=y` → `z = y`) on any
    # input that wasn't already formatter-clean — a change outside the rule's
    # scope. `patches_from_postwalk` diffs the original against the transformed
    # AST and patches only the changed `@doc` subtrees; `Sourceror.patch_string`
    # re-indents the multi-line heredoc replacement to the node's start column.
    Credence.RuleHelpers.patches_from_postwalk(ast, &fix_doc_node/1)
  end

  defp fix_doc_node({:@, meta, [{attr, attr_meta, [{:__block__, str_meta, [value]}]}]} = node)
       when attr in @doc_attrs and is_binary(value) do
    # Already a heredoc — leave it alone.  Sourceror records the delimiter
    # in the string block's metadata; re-processing a heredoc through
    # Sourceror.to_string corrupts indentation and destroys the file.
    if Keyword.get(str_meta, :delimiter) == ~s(""") or not raw_multi_line?(value) do
      node
    else
      # Sourceror needs the value to end with `\n` so the closing `"""`
      # renders on its own line — without it the closing delimiter ends up
      # glued to the last content line.
      content = unescape_value(value) |> ensure_trailing_newline()
      new_str_meta = Keyword.put(str_meta, :delimiter, ~s("""))
      {:@, meta, [{attr, attr_meta, [{:__block__, new_str_meta, [content]}]}]}
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
