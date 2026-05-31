defmodule Credence.Pattern.NoMapThenReduce do
  @moduledoc """
  Detects `Enum.map/2` creating an intermediate list consumed only by
  a single `Enum.reduce/3`.  The map should be fused into the reduce
  to avoid the intermediate allocation.

  ## Bad

      ages = Enum.map(people, & &1["age"])
      {sum, count} = Enum.reduce(ages, {0, 0}, fn x, {s, c} -> {s + x, c + 1} end)

  ## Good

      {sum, count} =
        Enum.reduce(people, {0, 0}, fn person, {s, c} ->
          {s + person["age"], c + 1}
        end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          {node, find_issues(statements) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # --- private ---

  defp find_issues(statements) do
    indexed = Enum.with_index(statements)

    Enum.flat_map(indexed, fn {stmt, idx} ->
      with {:ok, var_name, line} <- extract_map_assignment(stmt) do
        later = Enum.filter(indexed, fn {_, i} -> i > idx end)
        consumers = Enum.filter(later, fn {s, _} -> var_in_ast?(s, var_name) end)

        case consumers do
          [{consumer, consumer_idx}] ->
            between = Enum.filter(indexed, fn {_, i} -> i > idx and i < consumer_idx end)
            rebound? = Enum.any?(between, fn {s, _} -> rebinds_var?(s, var_name) end)

            if not rebound? and reduce_over_var?(consumer, var_name) do
              [
                %Issue{
                  rule: :no_map_then_reduce,
                  message:
                    "`Enum.map/2` result `#{var_name}` is only consumed by " <>
                      "`Enum.reduce/3` — fuse the map into the reduce to avoid " <>
                      "the intermediate list.",
                  meta: %{line: line}
                }
              ]
            else
              []
            end

          _ ->
            []
        end
      else
        _ -> []
      end
    end)
  end

  # Matches: var = Enum.map(enum, fun)
  defp extract_map_assignment({:=, meta, [lhs, rhs]}) do
    with {:ok, var_name} <- plain_var(lhs),
         true <- enum_map_call?(rhs) do
      {:ok, var_name, Keyword.get(meta, :line)}
    end
  end

  defp extract_map_assignment(_), do: :error

  defp plain_var({name, _, ctx})
       when is_atom(name) and is_atom(ctx) and name != :_,
       do: {:ok, name}

  defp plain_var(_), do: :error

  defp enum_map_call?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_, _]}), do: true
  defp enum_map_call?(_), do: false

  # Checks whether a statement's RHS (or the bare expression) is
  # Enum.reduce(var, ...) where var matches the map result.
  defp reduce_over_var?({:=, _, [_lhs, rhs]}, var), do: reduce_over_var_rhs?(rhs, var)
  defp reduce_over_var?(expr, var), do: reduce_over_var_rhs?(expr, var)

  defp reduce_over_var_rhs?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [{var_name, _, ctx} | _]},
         var
       )
       when is_atom(var_name) and is_atom(ctx),
       do: var_name == var

  defp reduce_over_var_rhs?(_, _), do: false

  defp var_in_ast?(ast, var_name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {^var_name, _, ctx} = node, _acc when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp rebinds_var?({:=, _, [lhs, _rhs]}, var_name), do: ast_has_var?(lhs, var_name)
  defp rebinds_var?(_, _), do: false

  defp ast_has_var?({name, _, ctx}, target) when is_atom(name) and is_atom(ctx),
    do: name == target

  defp ast_has_var?({_, _, args}, target) when is_list(args),
    do: Enum.any?(args, &ast_has_var?(&1, target))

  defp ast_has_var?(list, target) when is_list(list),
    do: Enum.any?(list, &ast_has_var?(&1, target))

  defp ast_has_var?(_, _), do: false
end
