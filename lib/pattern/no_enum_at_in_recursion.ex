defmodule Credence.Pattern.NoEnumAtInRecursion do
  @moduledoc """
  Performance rule: Flags `Enum.at/2` or `Enum.slice/2,3` with a dynamic
  (non-literal) offset inside **recursive** functions.

  Elixir lists are linked lists — `Enum.at/2` and `Enum.slice/3` are O(n).
  Using them with a changing index on every recursive call makes the overall
  complexity O(n × iterations). Instead, walk the list with pattern matching,
  or convert the list to a tuple up front and use `elem/2` for O(1) access.

  This rule catches the general case: any non-literal offset used with
  `Enum.at/2` or `Enum.slice/2,3` inside a recursive function. It does NOT
  fire when the offset is a literal integer or when the offset is a midpoint
  expression (those are handled by `NoEnumAtBinarySearch`).

  ## Check-only (no auto-fix)

  The fix requires structural changes: walking the list with pattern matching,
  or converting the list to a tuple in the calling function. This cannot be
  performed safely by an automated tool.

  ## Bad

      defp do_search(list, left, right, acc) when left < right do
        left_val = Enum.at(list, left)
        right_val = Enum.at(list, right)
        do_search(list, left + 1, right - 1, acc + left_val + right_val)
      end

      defp check_monotonic?(list, index, end_index) when index >= end_index, do: true
      defp check_monotonic?(list, index, end_index) do
        [a, b] = Enum.slice(list, index, 2)
        a < b and check_monotonic?(list, index + 1, end_index)
      end

  ## Good

      defp do_search(list, left, right, acc) when left < right do
        tuple = List.to_tuple(list)
        left_val = elem(tuple, left)
        right_val = elem(tuple, right)
        do_search(tuple, left + 1, right - 1, acc + left_val + right_val)
      end

      defp check_monotonic?([a, b | rest]) when a < b, do: check_monotonic?([b | rest])
      defp check_monotonic?(_), do: false
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    ast
    |> collect_function_defs()
    |> Enum.filter(fn {name, body} -> recursive?(body, name) end)
    |> Enum.flat_map(fn {_name, body} -> find_issues_in_body(body) end)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # -- collection ----------------------------------------------------------

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

  defp extract_func_name({:when, _, [{name, _, _} | _]}), do: name
  defp extract_func_name({name, _, _}) when is_atom(name), do: name
  defp extract_func_name(_), do: nil

  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      {:do, body} -> body
      _ -> nil
    end)
  end

  # -- recursion detection -------------------------------------------------

  defp recursive?(_, nil), do: true

  defp recursive?(body, func_name) do
    {_, found} =
      Macro.prewalk(body, false, fn
        {^func_name, _, args} = node, _ when is_list(args) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # -- issue detection -----------------------------------------------------

  defp find_issues_in_body(body) do
    {_, {issues, _mids}} =
      Macro.prewalk(body, {[], MapSet.new()}, fn
        # Track midpoint variable assignments
        {:=, _, [{var, _, _}, expr]} = node, {issues, mids} when is_atom(var) ->
          mids = if midpoint_expr?(expr), do: MapSet.put(mids, var), else: mids
          {node, {issues, mids}}

        # Direct: Enum.at(list, index)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [_list, index]} = node, {issues, mids} ->
          if flagged_index?(index, mids) do
            {node, {[trigger_issue(meta) | issues], mids}}
          else
            {node, {issues, mids}}
          end

        # Piped: list |> Enum.at(index)
        {:|>, meta, [_list, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [index]}]} = node,
        {issues, mids} ->
          if flagged_index?(index, mids) do
            {node, {[trigger_issue(meta) | issues], mids}}
          else
            {node, {issues, mids}}
          end

        # Direct: Enum.slice(list, offset, ...) — offset is the 2nd arg
        {{:., _, [{:__aliases__, _, [:Enum]}, :slice]}, meta, [_list, offset | _rest]} = node,
        {issues, mids} ->
          if flagged_index?(offset, mids) do
            {node, {[trigger_slice_issue(meta) | issues], mids}}
          else
            {node, {issues, mids}}
          end

        # Piped: list |> Enum.slice(offset, ...)
        {:|>, meta, [_list, {{:., _, [{:__aliases__, _, [:Enum]}, :slice]}, _, [offset | _rest]}]} =
        node, {issues, mids} ->
          if flagged_index?(offset, mids) do
            {node, {[trigger_slice_issue(meta) | issues], mids}}
          else
            {node, {issues, mids}}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  # Flag non-literal, non-midpoint indices.
  defp flagged_index?(index, mids) do
    not literal_integer?(index) and not midpoint_expr?(index) and not mid_var?(index, mids)
  end

  defp mid_var?({var, _, _}, mids) when is_atom(var), do: MapSet.member?(mids, var)
  defp mid_var?(_, _), do: false

  defp literal_integer?(n) when is_integer(n), do: true
  defp literal_integer?({:__block__, _, [n]}) when is_integer(n), do: true
  defp literal_integer?(_), do: false

  # Midpoint expressions are handled by NoEnumAtBinarySearch.
  defp midpoint_expr?({:+, _, [_low, {:div, _, [{:-, _, [_, _]}, d]}]}),
    do: unwrap_literal(d) == 2

  defp midpoint_expr?({:div, _, [{:+, _, [_, _]}, d]}),
    do: unwrap_literal(d) == 2

  defp midpoint_expr?({:+, _, [{:div, _, [{:-, _, [_, _]}, d]}, _]}),
    do: unwrap_literal(d) == 2

  defp midpoint_expr?(_), do: false

  defp unwrap_literal({:__block__, _, [val]}), do: val
  defp unwrap_literal(val), do: val

  defp trigger_issue(meta) do
    %Issue{
      rule: :no_enum_at_in_recursion,
      message:
        "Using `Enum.at/2` with a dynamic index inside a recursive function is O(n) per call. " <>
          "Walk the list with pattern matching, or convert to a tuple with `List.to_tuple/1` " <>
          "and use `elem/2` for O(1) access.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp trigger_slice_issue(meta) do
    %Issue{
      rule: :no_enum_at_in_recursion,
      message:
        "Using `Enum.slice/2,3` with a dynamic offset inside a recursive function is O(n) per call. " <>
          "Walk the list with pattern matching, or convert to a tuple with `List.to_tuple/1` " <>
          "and use `elem/2` for O(1) access.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
