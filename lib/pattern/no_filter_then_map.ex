defmodule Credence.Pattern.NoFilterThenMap do
  @moduledoc """
  Detects `Enum.filter/2` piped into `Enum.map/2`, which creates an
  unnecessary intermediate list.

  ## Why this matters

  LLMs produce filter-then-map pipelines that allocate an intermediate
  list from `Enum.filter` only to immediately consume it:

      # Flagged — intermediate list from filter
      numbers
      |> Enum.filter(fn x -> rem(x, 2) == 0 end)
      |> Enum.map(fn x -> x * x end)

      # Better — single pass, no intermediate list
      for x <- numbers, rem(x, 2) == 0, do: x * x

  A `for` comprehension with a guard fuses the filter and transform into
  a single traversal without allocating an intermediate list.

  ## Flagged patterns

  `Enum.filter(predicate)` piped into `Enum.map(transform)`.

  ## Not flagged

  - `Enum.filter(pred)` alone (no following `Enum.map`)
  - `Enum.map(transform)` without preceding `Enum.filter`
  - `Enum.filter |> Enum.map` where filter has no predicate (identity filter)
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Pipeline: ... |> Enum.filter(pred) |> Enum.map(transform)
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [first, second] ->
      if filter_step?(first) and map_step?(second) do
        {:ok, build_issue(first)}
      else
        nil
      end
    end)
    |> case do
      {:ok, _} = result -> result
      _ -> :error
    end
  end

  defp check_node(_), do: :error

  defp filter_step?({{:., _, [mod, :filter]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: enum_module?(mod)

  defp filter_step?(_), do: false

  defp map_step?({{:., _, [mod, :map]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: enum_module?(mod)

  defp map_step?(_), do: false

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp build_issue(filter_node) do
    {{:., meta, [_, :filter]}, _, _} = filter_node

    %Issue{
      rule: :no_filter_then_map,
      message: message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp message do
    "`Enum.filter/2` piped into `Enum.map/2` creates an unnecessary " <>
      "intermediate list. Use `for x <- enum, pred.(x), do: transform.(x)` instead."
  end
end
