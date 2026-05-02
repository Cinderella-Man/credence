defmodule Credence.Rule.NoMultipleEnumAt do
  @moduledoc """
  Readability & performance rule: Detects multiple `Enum.at/2` calls on the
  same variable with literal indices. Each `Enum.at/2` traverses the list
  from the head, so N calls cost O(N × len). Pattern matching destructures
  the list in a single pass.

  The rule fires when 3 or more `Enum.at(var, literal)` calls target the
  same variable, since that is a strong signal the code should use pattern
  matching instead.

  ## Bad

      sorted = Enum.sort(nums)
      min1 = Enum.at(sorted, 0)
      min2 = Enum.at(sorted, 1)
      max1 = Enum.at(sorted, -1)
      max2 = Enum.at(sorted, -2)

  ## Good

      sorted = Enum.sort(nums)
      [min1, min2 | _] = sorted
      [max1, max2 | _] = Enum.reverse(sorted)

      # Or with Enum.take:
      [min1, min2 | _] = Enum.sort(nums)
      [max1, max2 | _] = Enum.sort(nums, :desc)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @min_calls_to_flag 3

  @impl true
  def check(ast, _opts) do
    # Collect all Enum.at(var, literal_index) calls
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [{var_name, _, nil}, idx]} = node, acc
        when is_atom(var_name) ->
          if literal_index?(idx) do
            {node, [{var_name, Keyword.get(meta, :line)} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    # Group by variable name, flag those with 3+ calls
    calls
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.flat_map(fn {var_name, entries} ->
      if length(entries) >= @min_calls_to_flag do
        # Report at the line of the first call
        first_line = entries |> Enum.map(&elem(&1, 1)) |> Enum.min()

        [
          %Issue{
            rule: :no_multiple_enum_at,
            message:
              "`Enum.at/2` is called #{length(entries)} times on `#{var_name}`. " <>
                "Each call traverses the list from the head. Use pattern matching " <>
                "(e.g. `[a, b | _] = #{var_name}`) to destructure in a single pass.",
            meta: %{line: first_line}
          }
        ]
      else
        []
      end
    end)
  end

  # Matches positive integer literals (0, 1, 2, ...)
  defp literal_index?(idx) when is_integer(idx), do: true
  # Matches negative integer literals (-1, -2, ...) which parse as {:-, _, [int]}
  defp literal_index?({:-, _, [n]}) when is_integer(n), do: true
  defp literal_index?(_), do: false
end
