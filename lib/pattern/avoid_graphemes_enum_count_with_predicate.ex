defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicate do
  @moduledoc """
  Performance rule: Detects `Enum.count/2` (with a predicate) on the
  result of `String.graphemes/1`.

  `String.graphemes/1` eagerly allocates a list of every grapheme just to
  filter-count a subset. A lazy approach avoids this allocation.

  This rule is **not auto-fixable**. The naive replacement using
  `Stream.unfold(&String.next_grapheme/1)` can produce different results
  under Unicode normalization changes (e.g. after `String.downcase/1`),
  so the developer must choose the right approach for their context.

  ## Bad

      String.graphemes(string) |> Enum.count(&(&1 == "a"))
      Enum.count(String.graphemes(string), &(&1 == "a"))

  ## Suggested alternatives (manual)

      # Regex-based counting
      string |> String.graphemes() |> Enum.count(&(&1 == "a"))
      # could become:
      length(Regex.scan(~r/a/u, string))

      # Or if lazy streaming is needed, normalize first:
      string
      |> String.normalize(:nfc)
      |> Stream.unfold(&String.next_grapheme/1)
      |> Enum.count(&(&1 == "a"))
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe form: ... |> Enum.count(pred)
        {:|>, meta, [lhs, rhs]} = node, issues ->
          if enum_count_with_pred?(rhs) and immediate_graphemes?(lhs) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Direct: Enum.count(String.graphemes(...), pred)
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg, _pred]} = node, issues ->
          if graphemes_call?(arg) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # ── Detection helpers ─────────────────────────────────────────

  defp enum_count_with_pred?({{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _, args})
       when is_list(args),
       do: length(args) == 1

  defp enum_count_with_pred?(_), do: false

  defp immediate_graphemes?({:|>, _, [_, rhs]}), do: graphemes_call?(rhs)
  defp immediate_graphemes?(other), do: graphemes_call?(other)

  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args})
       when is_list(args),
       do: true

  defp graphemes_call?(_), do: false

  # ── Issue ─────────────────────────────────────────────────────

  defp build_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_enum_count_with_predicate,
      message: """
      Avoid `String.graphemes/1 |> Enum.count/2` — it allocates an
      intermediate list of all graphemes just to count matching ones.

      This cannot be auto-fixed because lazy-stream replacements may
      produce different results under Unicode normalization changes.
      Consider a regex-based approach or manual `Stream.unfold` with
      explicit `String.normalize(:nfc)`.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
