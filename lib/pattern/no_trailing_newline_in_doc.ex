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
  only newlines are trailing). Heredoc-style docs (`\"\"\"`) are not flagged
  or modified — their trailing `\\n` is structural and expected.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @doc_attrs [:doc, :moduledoc, :typedoc]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Sourceror shape: string wrapped in :__block__ with :delimiter meta.
        {:@, meta, [{attr, _, [{:__block__, str_meta, [value]}]}]} = node, acc
        when attr in @doc_attrs and is_binary(value) ->
          if not heredoc?(str_meta) and trailing_newline?(value) do
            {node, [build_issue(meta, attr) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  defp heredoc?(str_meta), do: Keyword.get(str_meta, :delimiter) == ~s(""")

  defp trailing_newline?(value),
    do: raw_trailing_only?(value) or real_trailing_only?(value)

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &fix_node/1)
  end

  defp fix_node({:@, meta, [{attr, attr_meta, [{:__block__, str_meta, [value]}]}]} = node)
       when attr in @doc_attrs and is_binary(value) do
    # Heredoc trailing \n is structural — don't strip it
    if Keyword.get(str_meta, :delimiter) == ~s(""") do
      node
    else
      case strip_trailing_doc_newline(value) do
        {:ok, cleaned} ->
          {:@, meta, [{attr, attr_meta, [{:__block__, str_meta, [cleaned]}]}]}

        :skip ->
          node
      end
    end
  end

  defp fix_node(node), do: node

  #
  # Sourceror preserves raw escape sequences in string values when
  # parsing fresh source: "text\n" → value is "text\\n" (backslash + n).
  #
  # But when an earlier rule's Sourceror.to_string() has already run,
  # it may unescaped \n into a real newline, so re-parsing produces
  # a value with an actual newline character.
  #
  # We handle both forms.

  defp strip_trailing_doc_newline(value) do
    cond do
      raw_trailing_only?(value) ->
        {:ok, drop_all_raw_escapes(value)}

      real_trailing_only?(value) ->
        {:ok, String.trim_trailing(value, "\n")}

      true ->
        :skip
    end
  end

  # Raw form: the value's last two characters are backslash + n, AND that
  # backslash actually opens an escape.
  #
  # `String.ends_with?(value, "\\n")` alone is not that test, and the difference
  # is a defect this rule shipped. Sourceror hands back the RAW text between the
  # quotes, so `@doc "abc\\n"` — which documents a literal backslash followed by
  # the letter n, no newline anywhere — arrives as `abc\\n` and satisfies
  # `ends_with?`. Stripping two characters then left `abc\\`, a dangling backslash
  # that escapes the closing quote, so the emitted source did not parse. The
  # safety invariant in `apply_rule_fix_with_status/3` caught it every time and
  # discarded the patch, which is why the rule reported six findings it never
  # repaired instead of shipping broken docs.
  #
  # An escape needs an ODD run of backslashes before the `n`: `\\n` is a newline,
  # `\\\\n` is a backslash and a letter.
  defp raw_trailing_only?(value) do
    raw_trailing_escape?(value) and not String.contains?(drop_all_raw_escapes(value), "\\n")
  end

  defp raw_trailing_escape?(value) do
    case Regex.run(~r/(\\+)n\z/, value) do
      [_match, slashes] -> rem(byte_size(slashes), 2) == 1
      nil -> false
    end
  end

  # Removes exactly the two-character trailing escape. Peeling them one at a time
  # and re-testing is what `String.trim_trailing/2` could not do: it strips a fixed
  # pattern blindly, so on `abc\\\\n\\n` it would eat into the escaped backslash. This
  # keeps `@doc "Some text.\\n\\n"` strippable — the documented "only newlines are
  # trailing" case — while leaving an escaped backslash intact.
  defp drop_all_raw_escapes(value) do
    if raw_trailing_escape?(value),
      do: drop_all_raw_escapes(binary_part(value, 0, byte_size(value) - 2)),
      else: value
  end

  # Resolved form: value ends with newline character (Sourceror on reformatted source)
  defp real_trailing_only?(value) do
    String.ends_with?(value, "\n") and
      not String.contains?(String.trim_trailing(value, "\n"), "\n")
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
