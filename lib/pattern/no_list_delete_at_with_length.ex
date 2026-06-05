defmodule Credence.Pattern.NoListDeleteAtWithLength do
  @moduledoc """
  Detects `List.delete_at(list, length(list) - 1)` where `length/1` is
  computed inline only to build the *last* index for `List.delete_at/2`,
  and rewrites it to the native negative index `List.delete_at(list, -1)`.

  ## Why this matters

  `length/1` is O(n) just to discover the last index, which
  `List.delete_at/2` already supports natively through negative
  indexing. The manual computation is redundant and obscures intent:

      # Bad — computes the index by hand
      List.delete_at(tail, length(tail) - 1)

      # Good — let delete_at count from the end
      List.delete_at(tail, -1)

  ## Detection scope

  Matches **only** `List.delete_at(x, length(x) - 1)` where `x` is the
  same variable in both positions. The offset must be exactly `1`.

  Larger offsets are deliberately **not** flagged: `List.delete_at(x,
  length(x) - K)` removes the single element `K` positions from the end,
  but `List.delete_at(x, -K)` is **not** equivalent — they diverge when
  the list is shorter than `K`. For `[1]` and `K = 2`,
  `List.delete_at([1], length([1]) - 2)` is `List.delete_at([1], -1) ==
  []`, whereas `List.delete_at([1], -2) == [1]` (the index is out of
  range, so nothing is removed). Only the `- 1` case has the same answer
  for every list length, so only it is rewritten. The length stored in a
  separate variable is also out of scope (that case may be handled by
  `no_length_based_indexing`).

  The rewrite stays a `List` operation rather than `Enum.drop/2` or
  `Enum.split/2` on purpose: `length/1` raises `ArgumentError` on
  non-lists (Range, Map, MapSet, ...), and `List.delete_at/2` raises the
  same `ArgumentError` on those inputs, so the rewrite preserves the
  raise-on-non-list contract exactly. `Enum.drop(x, -1)` would silently
  succeed on those inputs and change the answer.

  ## Bad

      List.delete_at(tail, length(tail) - 1)

  ## Good

      List.delete_at(tail, -1)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case match_delete_at_last(node) do
          {:ok, var_name, meta} ->
            {node, [build_issue(var_name, meta) | acc]}

          :error ->
            {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case match_delete_at_last(node) do
        {:ok, _var_name, _meta} -> rewrite_to_negative_index(node)
        :error -> node
      end
    end)
  end

  # Replaces the `length(x) - 1` index argument with the literal `-1`,
  # keeping every other part of the `List.delete_at/2` call verbatim.
  defp rewrite_to_negative_index({dot, meta, [list_arg, _index_arg]}) do
    {dot, meta, [list_arg, {:__block__, [], [-1]}]}
  end

  # Matches: List.delete_at(x, length(x) - 1)
  #   where x is the same variable in both spots.
  defp match_delete_at_last(
         {{:., _, [{:__aliases__, _, [:List]}, :delete_at]}, meta,
          [list_arg, {:-, _, [length_call, k_arg]}]}
       ) do
    with {:ok, list_var} <- extract_var(list_arg),
         {:ok, length_var} <- extract_length_var(length_call),
         true <- list_var == length_var,
         {:ok, 1} <- extract_pos_integer(k_arg) do
      {:ok, list_var, meta}
    else
      _ -> :error
    end
  end

  defp match_delete_at_last(_), do: :error

  defp extract_var({name, _, ctx}) when is_atom(name) and is_atom(ctx) and name != :_,
    do: {:ok, name}

  defp extract_var(_), do: :error

  defp extract_length_var({:length, _, [arg]}), do: extract_var(arg)

  defp extract_length_var({{:., _, [{:__aliases__, _, [:Kernel]}, :length]}, _, [arg]}),
    do: extract_var(arg)

  defp extract_length_var(_), do: :error

  defp extract_pos_integer({:__block__, _, [k]}) when is_integer(k) and k > 0, do: {:ok, k}
  defp extract_pos_integer(k) when is_integer(k) and k > 0, do: {:ok, k}
  defp extract_pos_integer(_), do: :error

  defp build_issue(var_name, meta) do
    %Issue{
      rule: :no_list_delete_at_with_length,
      message:
        "`List.delete_at(#{var_name}, length(#{var_name}) - 1)` computes the last index by " <>
          "hand with an O(n) `length/1` call. Use the native negative index " <>
          "`List.delete_at(#{var_name}, -1)` to drop the last element.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
