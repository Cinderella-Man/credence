defmodule Credence.Pattern.PreferSigilCharlist do
  @moduledoc """
  Rewrites a single-quoted charlist literal `'abc'` to the `~c"abc"` sigil.

  Single-quoted charlists are deprecated since Elixir 1.15 ("using single-quoted
  strings to represent charlists is deprecated") and become a hard error under
  `--warnings-as-errors`. LLMs emit them constantly when translating Python.
  `'abc'` and `~c"abc"` are the *same* value (`[97, 98, 99]`), so the rewrite is
  behaviour-identical — it only changes the source representation.

  ## Bad

      ['1', 'abc']

  ## Good

      [~c"1", ~c"abc"]

  ## Scope

  Only **non-interpolated** single-quoted charlist literals are matched, detected
  precisely via Sourceror's `delimiter: "'"` metadata — so a `'` inside a
  double-quoted string (`"don't"`) or an existing `~c` sigil is never touched.
  Interpolated charlists (a different AST shape) are left alone. Escaping (`"`,
  `\\`) in the result is handled by rendering the `~c"..."` sigil through
  Sourceror.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case single_quoted_charlist(node) do
          {:ok, _content} -> {node, [build_issue(node) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case single_quoted_charlist(node) do
          {:ok, content} -> {node, [patch(node, content) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # A single-quoted charlist literal is `{:__block__, meta, [charlist]}` where the
  # delimiter metadata is `'` and the single child is a proper list of integers
  # (the codepoints). Interpolated forms have a different shape and are skipped.
  defp single_quoted_charlist({:__block__, meta, [child]}) do
    if Keyword.get(meta, :delimiter) == "'" and charlist_value?(child) do
      {:ok, child}
    else
      :no
    end
  end

  defp single_quoted_charlist(_), do: :no

  # Non-empty list of integers. Empty `''` is skipped: it is rare and its
  # zero-width literal node has no reliable Sourceror range to patch.
  defp charlist_value?([_ | _] = list), do: Enum.all?(list, &is_integer/1)
  defp charlist_value?(_), do: false

  defp patch(node, content) do
    binary = List.to_string(content)
    sigil = {:sigil_c, [delimiter: "\""], [{:<<>>, [], [binary]}, []]}

    %{
      range: Sourceror.get_range(node),
      change: Sourceror.to_string(sigil)
    }
  end

  defp build_issue({:__block__, meta, _}) do
    %Issue{
      rule: :prefer_sigil_charlist,
      message: "Single-quoted charlists are deprecated. Use the `~c\"...\"` sigil instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
