defmodule Credence.Pattern.NoEnumAtInReduce do
  @moduledoc """
  Performance rule: Flags `Enum.at/2` with a dynamic (non-literal) index
  inside higher-order function callbacks (`Enum.reduce`, `Enum.reduce_while`,
  `Enum.map`, `Enum.each`, `Enum.filter`, `Enum.find`, `for`).

  Elixir lists are linked lists — `Enum.at/2` is O(n). Using it with a
  changing index on every iteration of a loop makes the overall complexity
  O(n × iterations), when converting the list to a tuple up front and
  using `elem/2` would give O(n) conversion + O(1) per access.

  This is the same anti-pattern as `NoEnumAtInRecursion`, but for
  higher-order function callbacks instead of recursive functions.

  This rule catches the general case: any non-literal index used with
  `Enum.at/2` inside a reduce/map/each/filter/find callback. It does NOT
  fire when the index is a literal integer (e.g. `Enum.at(list, 0)` is
  O(1) in practice).

  ## Check-only (no auto-fix)

  The fix requires structural changes: converting the list to a tuple
  before the loop, changing `Enum.at/2` to `elem/2` inside the callback,
  and potentially threading the tuple through the accumulator. This cannot
  be performed safely by an automated tool.

  ## Bad

      Enum.reduce_while(nums, {false, %{}}, fn {num, i}, {found, window} ->
        left = Enum.at(nums, i - k)
        {:cont, {found, Map.put(window, left, num)}}
      end)

  ## Good

      tuple = List.to_tuple(nums)

      Enum.reduce_while(nums, {false, %{}}, fn {num, i}, {found, window} ->
        left = elem(tuple, i - k)
        {:cont, {found, Map.put(window, left, num)}}
      end)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @reduce_fns ~w(reduce reduce_while map each filter find find_index flat_map reject)a

  @impl true
  def check(ast, _opts) do
    find_issues_in_reduce_callbacks(ast)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # -- issue detection -----------------------------------------------------

  defp find_issues_in_reduce_callbacks(ast) do
    {_, issues} =
      Macro.prewalk(ast, [], fn
        node, issues ->
          case extract_reduce_callback_body(node) do
            nil ->
              {node, issues}

            callback_body ->
              new_issues = find_enum_at_in_body(callback_body)
              {node, new_issues ++ issues}
          end
      end)

    Enum.reverse(issues)
  end

  # Extract the body of the callback from a higher-order function call.
  # Handles both direct and piped forms.
  defp extract_reduce_callback_body(node) do
    extract_direct_callback(node) || extract_piped_callback(node)
  end

  # Direct: Enum.reduce(list, acc, fn ... end)
  defp extract_direct_callback({{:., _, [{:__aliases__, _, [:Enum]}, func]}, _meta, args})
       when func in @reduce_fns do
    extract_fn_body(List.last(args))
  end

  # Direct: for x <- list, do: ... (comprehension)
  defp extract_direct_callback({:for, _meta, args}) when is_list(args) do
    Enum.find_value(args, fn
      {:do, body} -> body
      _ -> nil
    end)
  end

  defp extract_direct_callback(_), do: nil

  # Piped: list |> Enum.reduce(acc, fn ... end)
  defp extract_piped_callback(
         {:|>, _, [_left, {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _meta, args}]}
       )
       when func in @reduce_fns do
    extract_fn_body(List.last(args))
  end

  defp extract_piped_callback(_), do: nil

  # Extract the body from an anonymous function literal
  defp extract_fn_body({:fn, _, clauses}) when is_list(clauses) do
    # Return the body of the first clause (we'll scan all of them)
    case clauses do
      [{:->, _, [_args, body]} | _] -> body
      _ -> nil
    end
  end

  defp extract_fn_body(_), do: nil

  # Find Enum.at with dynamic index inside a callback body
  defp find_enum_at_in_body(body) do
    {_, {issues, _mids}} =
      Macro.prewalk(body, {[], MapSet.new()}, fn
        # Track midpoint variable assignments (to avoid false positives
        # for binary search patterns, mirroring NoEnumAtInRecursion)
        {:=, _, [{var, _, _}, expr]} = node, {issues, mids} when is_atom(var) ->
          mids = if midpoint_expr?(expr), do: MapSet.put(mids, var), else: mids
          {node, {issues, mids}}

        # Direct: Enum.at(list, index)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [_list, index]} = node,
        {issues, mids} ->
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
      rule: :no_enum_at_in_reduce,
      message:
        "Using `Enum.at/2` with a dynamic index inside a loop callback is O(n) per call. " <>
          "Convert the list to a tuple with `List.to_tuple/1` before the loop " <>
          "and use `elem/2` for O(1) access.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
