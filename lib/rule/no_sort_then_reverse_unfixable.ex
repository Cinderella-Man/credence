defmodule Credence.Rule.NoSortThenReverseUnfixable do
  @moduledoc """
  Readability rule: Detects the variable-mediated pattern of assigning
  `Enum.sort/1,2` to a variable and then calling `Enum.reverse/1` on that
  variable later in the same scope.

  This pattern cannot be safely auto-fixed because the sorted variable may be
  referenced in other expressions that expect ascending order, and a correct
  fix would require coordinated multi-site refactoring with scope analysis.

  ## Bad

      sorted = Enum.sort(nums)
      [min1, min2 | _] = sorted
      [max1, max2, max3 | _] = Enum.reverse(sorted)

  ## Good

      sorted = Enum.sort(nums)
      [min1, min2 | _] = sorted
      [max1, max2, max3 | _] = Enum.sort(nums, :desc)
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    # Pass 1: collect all variable names bound to Enum.sort(...)
    {_ast, sort_vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        # var = x |> Enum.sort()   (pipe nested inside assignment)
        {:=, _, [{var_name, _, nil}, {:|>, _, [_, sort_call]}]} = node, acc
        when is_atom(var_name) ->
          if sort_call?(sort_call) do
            {node, MapSet.put(acc, var_name)}
          else
            {node, acc}
          end

        # var = Enum.sort(...)
        {:=, _, [{var_name, _, nil}, sort_call]} = node, acc
        when is_atom(var_name) ->
          if sort_call?(sort_call) do
            {node, MapSet.put(acc, var_name)}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if MapSet.size(sort_vars) == 0 do
      []
    else
      # Pass 2: find Enum.reverse(var) or var |> Enum.reverse()
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          # Enum.reverse(sorted_var)
          {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, meta, [{var_name, _, nil}]} = node,
          acc
          when is_atom(var_name) ->
            if MapSet.member?(sort_vars, var_name) do
              {node, [build_issue(meta) | acc]}
            else
              {node, acc}
            end

          # sorted_var |> Enum.reverse()
          {:|>, meta,
           [
             {var_name, _, nil},
             {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, _}
           ]} = node,
          acc
          when is_atom(var_name) ->
            if MapSet.member?(sort_vars, var_name) do
              {node, [build_issue(meta) | acc]}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix(source, _opts), do: source

  defp sort_call?({{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, _}), do: true
  defp sort_call?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_sort_then_reverse,
      message:
        "Avoid `Enum.sort/1` followed by `Enum.reverse/1`. " <>
          "Use `Enum.sort(list, :desc)` instead to sort in descending order in a single pass.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
