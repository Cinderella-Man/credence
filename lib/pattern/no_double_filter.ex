defmodule Credence.Pattern.NoDoubleFilter do
  @moduledoc """
  Detects two `Enum.filter/2` calls on the **same** enumerable in the
  same block scope, which can be replaced with a single `Enum.split_with/2`.

  ## Bad

      positives = Enum.filter(numbers, &(&1 >= 0))
      negatives = Enum.filter(numbers, &(&1 < 0))

  ## Good

      {positives, negatives} = Enum.split_with(numbers, &(&1 >= 0))
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case node do
          {:__block__, _, statements} ->
            block_issues = find_double_filters(statements)
            {node, issues ++ block_issues}

          _ ->
            {node, issues}
        end
      end)

    issues
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp find_double_filters(statements) do
    filters =
      Enum.flat_map(statements, fn
        {:=, meta, [_target, filter_call]} ->
          case extract_filter_key(filter_call) do
            {:ok, key} -> [{key, meta}]
            :error -> []
          end

        _ ->
          []
      end)

    filters
    |> Enum.group_by(fn {key, _} -> key end)
    |> Enum.flat_map(fn
      {_, [_single]} ->
        []

      {{name, _ctx}, metas} ->
        Enum.map(metas, fn {_, meta} ->
          %Issue{
            rule: :no_double_filter,
            message:
              "Two `Enum.filter/2` calls on `#{name}`. " <>
                "Use `Enum.split_with/2` instead for a single pass.",
            meta: %{line: Keyword.get(meta, :line)}
          }
        end)
    end)
  end

  defp extract_filter_key(
         {{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, [{name, _, ctx} | _]}
       )
       when is_atom(name) and is_atom(ctx) do
    {:ok, {name, ctx}}
  end

  defp extract_filter_key(_), do: :error
end
