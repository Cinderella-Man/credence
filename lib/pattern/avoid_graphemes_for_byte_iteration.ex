defmodule Credence.Pattern.AvoidGraphemesForByteIteration do
  @moduledoc """
  Check-only rule: Detects `String.graphemes/1` piped into `Enum.all?/2`,
  `Enum.any?/2`, or `Enum.each/2`.

  `String.graphemes/1` splits into grapheme strings — each a single-char
  binary. When the predicate only needs to inspect byte values (e.g. range
  guards), `String.to_charlist/1` is more direct: it yields integers
  without the intermediate binary wrapping.

  This rule is check-only because rewriting the predicate from
  binary-matching to integer-matching cannot be done reliably in the
  general case.

  ## Bad

      string |> String.graphemes() |> Enum.all?(&hex_digit?/1)
      string |> String.graphemes() |> Enum.any?(&(?0 <= &1 and &1 <= ?9))

  ## Good

      string |> String.to_charlist() |> Enum.all?(&hex_digit?/1)
      String.to_charlist(string) |> Enum.all?(&hex_digit?/1)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipe: ... |> String.graphemes() |> Enum.all?(pred)
        {:|>, meta, [lhs, rhs]} = node, issues ->
          if iteration_call?(rhs) and immediate_graphemes?(lhs) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Enum.all?(pred), Enum.any?(pred), Enum.each(pred)
  defp iteration_call?({{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, [pred]})
       when func in [:all?, :any?, :each] and is_tuple(pred),
       do: true

  defp iteration_call?(_), do: false

  defp immediate_graphemes?({:|>, _, [_, rhs]}), do: graphemes_call?(rhs)
  defp immediate_graphemes?(other), do: graphemes_call?(other)

  defp graphemes_call?({{:., _, [{:__aliases__, _, [:String]}, :graphemes]}, _, args})
       when is_list(args),
       do: true

  defp graphemes_call?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :avoid_graphemes_for_byte_iteration,
      message: """
      `String.graphemes/1` produces single-char binaries, but `Enum.all?/2`, \
      `Enum.any?/2`, and `Enum.each/2` only consume values — they don't need \
      binary graphemes. `String.to_charlist/1` yields integers directly and \
      avoids the intermediate binary wrapping.

      Replace `String.graphemes/1` with `String.to_charlist/1`:

          # Before (creates binary graphemes):
          string |> String.graphemes() |> Enum.all?(&valid?/1)

          # After (yields integers directly):
          string |> String.to_charlist() |> Enum.all?(&valid?/1)
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
