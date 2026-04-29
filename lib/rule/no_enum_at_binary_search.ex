defmodule Credence.Rule.NoEnumAtBinarySearch do
  @moduledoc """
  Performance rule: Flags potential binary search patterns using `Enum.at/2`.

  Elixir lists are linked lists. `Enum.at/2` is an O(n) operation. Using it
  inside a binary search (which usually expects O(1) access) results in
  O(n log n) complexity, defeating the purpose of the algorithm.

  If random access is required, convert the list to a tuple first using
  `List.to_tuple/1` and use `elem/2`.

  ## Bad

      mid = low + div(high - low, 2)
      mid_val = Enum.at(list, mid) # O(n) traversal inside a loop

  ## Good

      tuple = List.to_tuple(list)
      # ... inside loop:
      mid_val = elem(tuple, mid) # O(1) access
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, {issues, _mids}} =
      Macro.prewalk(ast, {[], MapSet.new()}, fn
        # Capture mid = <midpoint math>
        {:=, _, [{var, _, _}, expr]} = node, {issues, mids} when is_atom(var) ->
          mids =
            if midpoint_expr?(expr) do
              MapSet.put(mids, var)
            else
              mids
            end

          {node, {issues, mids}}

        # Detect Enum.at(list, mid)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [_list, index]} = node, {issues, mids} ->
          cond do
            is_mid_var?(index, mids) ->
              {node, {[trigger_issue(meta) | issues], mids}}

            midpoint_expr?(index) ->
              # INLINE midpoint math like Enum.at(list, low + div(...))
              {node, {[trigger_issue(meta) | issues], mids}}

            true ->
              {node, {issues, mids}}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  defp is_mid_var?({var, _, _}, mids) when is_atom(var) do
    MapSet.member?(mids, var)
  end

  defp is_mid_var?(_, _), do: false

  defp midpoint_expr?(expr) do
    case expr do
      # low + div(high - low, 2)
      {:+, _, [_low, {:div, _, [{:-, _, [_high, _low2]}, 2]}]} ->
        true

      # div(high + low, 2)
      {:div, _, [{:+, _, [_low, _high]}, 2]} ->
        true

      # variants like div(high - low, 2) + low
      {:+, _, [{:div, _, [{:-, _, [_high, _low]}, 2]}, _low2]} ->
        true

      _ ->
        false
    end
  end

  defp trigger_issue(meta) do
    %Issue{
      rule: :no_enum_at_binary_search,
      severity: :warning,
      message:
        "Using `Enum.at/2` with a dynamic index on a list is O(n). " <>
          "For binary search or frequent random access, convert the list " <>
          "to a tuple with `List.to_tuple/1` and use `elem/2` for O(1) access.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
