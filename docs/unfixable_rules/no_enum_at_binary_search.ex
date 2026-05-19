defmodule Credence.Pattern.NoEnumAtBinarySearch do
  @moduledoc """
  Performance rule: Flags `Enum.at/2` inside **recursive** binary search functions.

  Elixir lists are linked lists. `Enum.at/2` is an O(n) operation. Using it
  inside a recursive binary search results in O(n log n) complexity, defeating
  the purpose of the algorithm.

  ## Not auto-fixable

  Recursive functions require a manual refactor: create a wrapper function
  that calls `List.to_tuple/1`, change the recursive helper's signature to
  accept the tuple, and update all recursive call sites. This structural
  change cannot be performed safely by an automated tool.

  ## Bad

      def search(list, target, low, high) when low <= high do
        mid = low + div(high - low, 2)
        mid_val = Enum.at(list, mid)  # O(n) on every recursive call
        cond do
          mid_val == target -> mid
          mid_val < target  -> search(list, target, mid + 1, high)
          true              -> search(list, target, low, mid - 1)
        end
      end

  ## Good

      def search(list, target) do
        tuple = List.to_tuple(list)
        do_search(tuple, target, 0, tuple_size(tuple) - 1)
      end

      defp do_search(tuple, target, low, high) when low <= high do
        mid = low + div(high - low, 2)
        mid_val = elem(tuple, mid)  # O(1)
        cond do
          mid_val == target -> mid
          mid_val < target  -> do_search(tuple, target, mid + 1, high)
          true              -> do_search(tuple, target, low, mid - 1)
        end
      end

  See also `Credence.Pattern.NoEnumAtMidpointAccess` which catches the same
  anti-pattern in non-recursive functions and can auto-fix it.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    ast
    |> collect_function_defs()
    |> Enum.filter(fn {name, body} -> recursive?(body, name) end)
    |> Enum.flat_map(fn {_name, body} -> find_issues_in_body(body) end)
  end

  defp collect_function_defs(ast) do
    {_, fns} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head, body_kw]} = node, acc
        when kind in [:def, :defp] and is_list(body_kw) ->
          name = extract_func_name(head)
          body = extract_do_body(body_kw)

          if name != nil and body != nil do
            {node, [{name, body} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    fns
  end

  defp find_issues_in_body(body) do
    {_, {issues, _mids}} =
      Macro.prewalk(body, {[], MapSet.new()}, fn
        {:=, _, [{var, _, _}, expr]} = node, {issues, mids} when is_atom(var) ->
          mids = if midpoint_expr?(expr), do: MapSet.put(mids, var), else: mids
          {node, {issues, mids}}

        # Direct: Enum.at(list, mid)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [_list, index]} = node, {issues, mids} ->
          if flagged_index?(index, mids) do
            {node, {[trigger_issue(meta) | issues], mids}}
          else
            {node, {issues, mids}}
          end

        # Piped: list |> Enum.at(mid)
        {:|>, meta, [_list, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [index]}]} = node,
        {issues, mids} ->
          if flagged_index?(index, mids) do
            {node, {[trigger_issue(meta) | issues], mids}}
          else
            {node, {issues, mids}}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      {:do, body} -> body
      _ -> nil
    end)
  end

  defp extract_func_name({:when, _, [{name, _, _} | _]}), do: name
  defp extract_func_name({name, _, _}) when is_atom(name), do: name
  defp extract_func_name(_), do: nil

  defp recursive?(_, nil), do: true

  defp recursive?(body, func_name) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {^func_name, _, args} = node, _ when is_list(args) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp flagged_index?(index, mids) do
    mid_var?(index, mids) or midpoint_expr?(index)
  end

  defp mid_var?({var, _, _}, mids) when is_atom(var), do: MapSet.member?(mids, var)
  defp mid_var?(_, _), do: false

  defp unwrap_literal({:__block__, _, [val]}), do: val
  defp unwrap_literal(val), do: val

  defp midpoint_expr?({:+, _, [_low, {:div, _, [{:-, _, [_, _]}, d]}]}),
    do: unwrap_literal(d) == 2

  defp midpoint_expr?({:div, _, [{:+, _, [_, _]}, d]}),
    do: unwrap_literal(d) == 2

  defp midpoint_expr?({:+, _, [{:div, _, [{:-, _, [_, _]}, d]}, _]}),
    do: unwrap_literal(d) == 2

  defp midpoint_expr?(_), do: false

  defp trigger_issue(meta) do
    %Issue{
      rule: :no_enum_at_binary_search,
      message:
        "Using `Enum.at/2` with a dynamic index on a list is O(n). " <>
          "For binary search or frequent random access, convert the list " <>
          "to a tuple with `List.to_tuple/1` and use `elem/2` for O(1) access.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
