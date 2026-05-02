defmodule Credence.Rule.NoDoubleSortSameList do
  @moduledoc """
  Performance rule: Detects sorting the same list twice — once ascending and
  once descending — when a single sort plus `Enum.reverse/1` would suffice.

  `Enum.sort(list, :desc)` is typically implemented as sort-then-reverse
  internally, so calling both `Enum.sort(list)` and `Enum.sort(list, :desc)`
  on the same variable performs two full O(n log n) sorts. Sorting once and
  reversing the result is O(n log n) + O(n).

  ## Bad

      asc = Enum.sort(arr)
      desc = Enum.sort(arr, :desc)

  ## Good

      asc = Enum.sort(arr)
      desc = Enum.reverse(asc)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    # Collect all Enum.sort calls that are bound to a variable,
    # recording the source variable, direction, and line number.
    {_ast, sort_calls} =
      Macro.prewalk(ast, [], fn
        # Direct call: var = Enum.sort(source) or Enum.sort(source, :desc)
        {:=, meta, [_, {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args}]} = node, acc ->
          case extract_sort_info(args) do
            {source, direction} ->
              {node, [{source, direction, Keyword.get(meta, :line)} | acc]}

            nil ->
              {node, acc}
          end

        # Piped: var = source |> Enum.sort() or source |> Enum.sort(:desc)
        {:=, meta,
         [
           _,
           {:|>, _,
            [
              source_ast,
              {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args}
            ]}
         ]} = node,
        acc ->
          source = extract_source_var(source_ast)

          direction =
            case args do
              [] -> :asc
              [:desc] -> :desc
              [:asc] -> :asc
              _ -> nil
            end

          if source != nil and direction != nil do
            {node, [{source, direction, Keyword.get(meta, :line)} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    # Group by source variable, flag those that have both :asc and :desc
    sort_calls
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.flat_map(fn {source, calls} ->
      directions = calls |> Enum.map(&elem(&1, 1)) |> MapSet.new()

      if MapSet.member?(directions, :asc) and MapSet.member?(directions, :desc) do
        # Report at the line of the :desc sort (the redundant one)
        {_, _, line} = Enum.find(calls, fn {_, dir, _} -> dir == :desc end)

        [
          %Issue{
            rule: :no_double_sort_same_list,
            message:
              "The list `#{source}` is sorted twice (ascending and descending). " <>
                "Sort once and use `Enum.reverse/1` on the result instead: " <>
                "`desc = Enum.reverse(asc)`.",
            meta: %{line: line}
          }
        ]
      else
        []
      end
    end)
  end

  # Extract source variable name and sort direction from direct Enum.sort args
  defp extract_sort_info([{source, _, nil}]) when is_atom(source), do: {source, :asc}
  defp extract_sort_info([{source, _, nil}, :desc]) when is_atom(source), do: {source, :desc}
  defp extract_sort_info([{source, _, nil}, :asc]) when is_atom(source), do: {source, :asc}
  defp extract_sort_info(_), do: nil

  # Extract the root variable name from a pipe chain or plain variable
  defp extract_source_var({name, _, nil}) when is_atom(name), do: name
  defp extract_source_var({:|>, _, [left, _]}), do: extract_source_var(left)
  defp extract_source_var(_), do: nil
end
