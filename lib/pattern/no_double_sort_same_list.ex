defmodule Credence.Pattern.NoDoubleSortSameList do
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
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    collect_bound_sorts(ast)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.flat_map(fn {source, calls} ->
      directions = calls |> Enum.map(&elem(&1, 1)) |> MapSet.new()

      if MapSet.member?(directions, :asc) and MapSet.member?(directions, :desc) do
        # Report at the line of the :desc sort (the redundant one)
        {_, _, line, _} = Enum.find(calls, fn {_, dir, _, _} -> dir == :desc end)

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

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)
    bindings = collect_bound_sorts(ast)

    replacements =
      bindings
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.reduce(%{}, fn {source_name, calls}, map ->
        dirs = calls |> Enum.map(&elem(&1, 1)) |> MapSet.new()

        if MapSet.member?(dirs, :asc) and MapSet.member?(dirs, :desc) do
          {_, _, _, asc_var} = Enum.find(calls, fn {_, d, _, _} -> d == :asc end)
          Map.put(map, source_name, asc_var)
        else
          map
        end
      end)

    if map_size(replacements) == 0 do
      source
    else
      ast
      |> Macro.postwalk(fn
        {:=, meta, [{bound, _, nil} = lhs, rhs]} = node when is_atom(bound) ->
          case rhs_sort_info(rhs) do
            {src, :desc} when is_map_key(replacements, src) ->
              asc_var = Map.fetch!(replacements, src)
              {:=, meta, [lhs, enum_reverse_call({asc_var, [], nil})]}

            _ ->
              node
          end

        node ->
          node
      end)
      |> Sourceror.to_string()
    end
  end

  # Returns [{source_name, direction, line, bound_var_name}, ...]
  defp collect_bound_sorts(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {:=, meta, [{bound, _, nil}, rhs]} = node, acc when is_atom(bound) ->
          case rhs_sort_info(rhs) do
            {source, direction} ->
              {node, [{source, direction, Keyword.get(meta, :line), bound} | acc]}

            nil ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # Direct call: Enum.sort(source) / Enum.sort(source, :desc)
  defp rhs_sort_info({{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args}) do
    extract_sort_info(args)
  end

  # Piped: source |> Enum.sort() / source |> Enum.sort(:desc)
  defp rhs_sort_info(
         {:|>, _, [source_ast, {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args}]}
       ) do
    source = extract_source_var(source_ast)

    direction =
      case args do
        [] -> :asc
        [dir_arg] -> unwrap_atom(dir_arg)
        _ -> nil
      end

    if source != nil and direction in [:asc, :desc], do: {source, direction}, else: nil
  end

  defp rhs_sort_info(_), do: nil

  # Extract source variable name and sort direction from direct Enum.sort args
  defp extract_sort_info([{source, _, nil}]) when is_atom(source), do: {source, :asc}

  defp extract_sort_info([{source, _, nil}, dir_arg]) when is_atom(source) do
    case unwrap_atom(dir_arg) do
      :desc -> {source, :desc}
      :asc -> {source, :asc}
      _ -> nil
    end
  end

  defp extract_sort_info(_), do: nil

  # Extract the root variable name from a pipe chain or plain variable
  defp extract_source_var({name, _, nil}) when is_atom(name), do: name
  defp extract_source_var({:|>, _, [left, _]}), do: extract_source_var(left)
  defp extract_source_var(_), do: nil

  defp enum_reverse_call(arg) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], [arg]}
  end

  # Sourceror wraps literal atoms in {:__block__, meta, [atom]} to attach
  # positional metadata. This helper normalises both representations.
  defp unwrap_atom({:__block__, _, [atom]}) when is_atom(atom), do: atom
  defp unwrap_atom(atom) when is_atom(atom), do: atom
  defp unwrap_atom(_), do: nil
end
