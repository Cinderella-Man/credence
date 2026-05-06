defmodule Credence.Pattern.NoTrailingNewlineInDoc do
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

  Strips trailing `\\n` from single-line doc strings (strings where the
  only newlines are trailing). Heredoc-style docs are not modified.
  """

  use Credence.Rule
  alias Credence.Issue

  @doc_attrs [:doc, :moduledoc, :typedoc]

  @impl true
  def fixable?, do: true

  # ── Check (Code.string_to_quoted AST — escapes resolved) ───────

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

  # ── Fix (Sourceror AST — escapes may be raw OR resolved) ───────

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)

    if has_fixable_doc?(ast) do
      fixed_ast = Macro.postwalk(ast, &fix_node/1)
      result = Sourceror.to_string(fixed_ast)

      if String.ends_with?(source, "\n") and not String.ends_with?(result, "\n") do
        result <> "\n"
      else
        result
      end
    else
      source
    end
  end

  defp fix_node({:@, meta, [{attr, attr_meta, [{:__block__, str_meta, [value]}]}]} = node)
       when attr in @doc_attrs and is_binary(value) do
    case strip_trailing_doc_newline(value) do
      {:ok, cleaned} ->
        {:@, meta, [{attr, attr_meta, [{:__block__, str_meta, [cleaned]}]}]}

      :skip ->
        node
    end
  end

  defp fix_node(node), do: node

  # ── Pre-check ───────────────────────────────────────────────────

  defp has_fixable_doc?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:@, _, [{attr, _, [{:__block__, _, [value]}]}]} = node, acc
        when attr in @doc_attrs and is_binary(value) ->
          {node, acc or fixable_value?(value)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # ── Value analysis and stripping ────────────────────────────────
  #
  # Sourceror preserves raw escape sequences in string values when
  # parsing fresh source: "text\n" → value is "text\\n" (backslash + n).
  #
  # But when an earlier rule's Sourceror.to_string() has already run,
  # it may unescaped \n into a real newline, so re-parsing produces
  # a value with an actual newline character.
  #
  # We handle both forms.

  defp fixable_value?(value) do
    raw_trailing_only?(value) or real_trailing_only?(value)
  end

  defp strip_trailing_doc_newline(value) do
    cond do
      raw_trailing_only?(value) ->
        {:ok, String.trim_trailing(value, "\\n")}

      real_trailing_only?(value) ->
        {:ok, String.trim_trailing(value, "\n")}

      true ->
        :skip
    end
  end

  # Raw form: value ends with literal backslash + n (Sourceror on fresh source)
  defp raw_trailing_only?(value) do
    String.ends_with?(value, "\\n") and
      not String.contains?(String.trim_trailing(value, "\\n"), "\\n")
  end

  # Resolved form: value ends with newline character (Sourceror on reformatted source)
  defp real_trailing_only?(value) do
    String.ends_with?(value, "\n") and
      not String.contains?(String.trim_trailing(value, "\n"), "\n")
  end

  # For check (Code.string_to_quoted — always resolved)
  defp trailing_newline_only?(value), do: real_trailing_only?(value)

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
