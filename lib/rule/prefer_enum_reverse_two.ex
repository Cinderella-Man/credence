defmodule Credence.Rule.PreferEnumReverseTwo do
  @moduledoc """
  Performance rule: Flags `Enum.reverse(list) ++ other_list`.

  `Enum.reverse/1` creates a new list, and `++` traverses that new list
  entirely to append the second. This is a 2-pass operation.

  Using `Enum.reverse/2` performs both actions in a single optimized pass.

  ## Bad

      defp do_merge([], l2, acc), do: Enum.reverse(acc) ++ l2

  ## Good

      defp do_merge([], l2, acc), do: Enum.reverse(acc, l2)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Matches: Enum.reverse(acc) ++ tail
        {:++, meta, [{{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [_acc]}, _tail]} = node,
        issues ->
          {node, [create_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp create_issue(meta) do
    %Issue{
      rule: :prefer_enum_reverse_two,
      severity: :warning,
      message:
        "Pattern to avoid:\n" <>
          "  Enum.reverse(list1) ++ list2\n\n" <>
          "Use instead:\n" <>
          "  Enum.reverse(list1, list2)\n\n" <>
          "This applies regardless of variable names.\n\n" <>
          "Reason:\n" <>
          "- Enum.reverse(list1) creates a new reversed list.\n" <>
          "- The ++ operator then traverses that entire list again to append list2.\n" <>
          "- This causes two full traversals.\n\n" <>
          "Enum.reverse(list1, list2) performs the same operation in a single pass,\n" <>
          "which is more efficient in both time and memory.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
