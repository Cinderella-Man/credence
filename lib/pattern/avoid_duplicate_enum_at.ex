defmodule Credence.Pattern.AvoidDuplicateEnumAt do
  @moduledoc """
  Detects two `Enum.at` calls on the same list variable in one `if` condition.

  Two `Enum.at` calls on the same list in one condition traverse the list
  twice. By binding the results to variables before the conditional, each
  element is fetched only once and the condition reads more clearly.

  ## Bad

      if Enum.at(nums, mid) > Enum.at(nums, high) do
        findminindex(nums, mid + 1, high)
      else
        findminindex(nums, low, mid)
      end

  ## Good

      mid_elem = Enum.at(nums, mid)
      high_elem = Enum.at(nums, high)

      if mid_elem > high_elem do
        findminindex(nums, mid + 1, high)
      else
        findminindex(nums, low, mid)
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, _branches]} = node, issues ->
          case duplicate_enum_at_calls(condition) do
            [] -> {node, issues}
            _ -> {node, [build_issue(meta) | issues]}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      {:if, meta, [condition, branches]} = node ->
        calls = duplicate_enum_at_calls(condition)

        if calls == [] do
          node
        else
          {bindings, new_condition} = rewrite_with_bindings(condition, calls)
          {:__block__, [], bindings ++ [{:if, meta, [new_condition, branches]}]}
        end

      node ->
        node
    end)
  end

  # Collect all Enum.at calls on the same list variable in the condition,
  # returning only those that appear 2+ times for the same list.
  defp duplicate_enum_at_calls(condition) do
    all_calls = collect_enum_at_calls(condition)

    all_calls
    |> Enum.group_by(fn {list_var, _idx} -> list_var end)
    |> Enum.filter(fn {_list_var, group} -> length(group) >= 2 end)
    |> Enum.flat_map(fn {_list_var, group} -> group end)
    |> Enum.uniq_by(fn {_list_var, idx} -> normalize_idx(idx) end)
  end

  # Walk an expression and collect all Enum.at(list_var, idx) calls.
  defp collect_enum_at_calls(ast) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{name, _, nil}, idx]} = node,
        acc
        when is_atom(name) ->
          {node, [{name, idx} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(calls)
  end

  # Normalize an index AST node for deduplication comparison.
  defp normalize_idx({name, _meta, ctx}) when is_atom(name), do: {:var, name, ctx}
  defp normalize_idx({:__block__, _meta, [val]}), do: {:lit, val}
  defp normalize_idx(other), do: {:other, other}

  # Build bindings and rewrite the condition to use bound variables.
  defp rewrite_with_bindings(condition, calls) do
    indexed_calls = Enum.with_index(calls)

    name_map =
      indexed_calls
      |> Enum.map(fn {{list_var, idx}, i} ->
        var_name = var_name_for_idx(idx, i)
        {{list_var, normalize_idx(idx)}, var_name}
      end)
      |> Map.new()

    bindings =
      Enum.map(indexed_calls, fn {{list_var, idx}, _i} ->
        var_name = Map.fetch!(name_map, {list_var, normalize_idx(idx)})
        create_binding(var_name, list_var, idx)
      end)

    new_condition =
      Macro.postwalk(condition, fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{name, _, nil}, idx]} = node
        when is_atom(name) ->
          case Map.fetch(name_map, {name, normalize_idx(idx)}) do
            {:ok, var_name} -> {var_name, [], nil}
            :error -> node
          end

        node ->
          node
      end)

    {bindings, new_condition}
  end

  # Generate a variable name for an extracted Enum.at index.
  defp var_name_for_idx({name, _, ctx}, _i) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) do
    :"#{name}_elem"
  end

  defp var_name_for_idx({:__block__, _, [n]}, _i) when is_integer(n) do
    :"elem_#{n}"
  end

  defp var_name_for_idx(_, i) do
    :"enum_at_elem_#{i}"
  end

  # Build an AST node for `var_name = Enum.at(list_var, idx)`.
  defp create_binding(var_name, list_var, idx) do
    {:=, [],
     [
       {var_name, [], nil},
       {{:., [], [{:__aliases__, [], [:Enum]}, :at]}, [],
        [{list_var, [], nil}, clean_idx(idx)]}
     ]}
  end

  # Strip metadata from an index AST node for use in generated code.
  defp clean_idx({name, _meta, ctx}) when is_atom(name), do: {name, [], ctx}
  defp clean_idx({:__block__, _meta, [val]}), do: {:__block__, [], [val]}
  defp clean_idx(other), do: other

  defp build_issue(meta) do
    %Issue{
      rule: :avoid_duplicate_enum_at,
      message:
        "Two `Enum.at` calls on the same list in one condition. " <>
          "Bind the results to variables before the conditional for clarity and efficiency.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
