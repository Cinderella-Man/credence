defmodule Credence.Rule.NoSortThenReverse do
  @moduledoc """
  Performance & readability rule: Detects the pattern of calling `Enum.sort/1`
  followed by `Enum.reverse/1` on the result.

  Sorting ascending then reversing is equivalent to `Enum.sort(list, :desc)`
  (or `Enum.sort(list, &>=/2)`) but wastes a full O(n) pass for the reversal.

  ## Bad

      sorted = Enum.sort(nums)
      top = Enum.reverse(sorted)

      # or in a pipeline
      nums |> Enum.sort() |> Enum.reverse()

  ## Good

      sorted_desc = Enum.sort(nums, :desc)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline form: Enum.sort(...) |> Enum.reverse()
        {:|>, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, _},
           {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, _}
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        # Nested call form: Enum.reverse(Enum.sort(...))
        {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, _}
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        # Variable binding form:
        # sorted = Enum.sort(x)    -- we track these
        # ... Enum.reverse(sorted) -- and match here
        #
        # This requires two-pass or stateful tracking. We handle the simpler
        # pipeline/nested forms above and use a second pass for the variable form.
        node, issues ->
          {node, issues}
      end)

    # Second pass: detect variable-mediated sort-then-reverse
    bound_issues = find_variable_sort_reverse(ast)

    Enum.reverse(issues) ++ bound_issues
  end

  defp find_variable_sort_reverse(ast) do
    # Pass 1: collect all variable names bound to Enum.sort(...)
    {_ast, sort_vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _, [{var_name, _, nil}, {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, _}]} =
            node,
        acc
        when is_atom(var_name) ->
          {node, MapSet.put(acc, var_name)}

        # Also match: sorted = x |> Enum.sort()
        {:=, _,
         [
           {var_name, _, nil},
           {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, _}]}
         ]} = node,
        acc
        when is_atom(var_name) ->
          {node, MapSet.put(acc, var_name)}

        node, acc ->
          {node, acc}
      end)

    if MapSet.size(sort_vars) == 0 do
      []
    else
      # Pass 2: find Enum.reverse(var) where var is in sort_vars
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, meta, [{var_name, _, nil}]} = node,
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

  defp build_issue(meta) do
    %Issue{
      rule: :no_sort_then_reverse,
      severity: :warning,
      message:
        "Avoid `Enum.sort/1` followed by `Enum.reverse/1`. Use `Enum.sort(list, :desc)` instead to sort in descending order in a single pass.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
