defmodule Credence.Pattern.NoFilterThenFlatMap do
  @moduledoc """
  Detects `Enum.filter/2` piped into `Enum.flat_map/2`, which creates an
  unnecessary intermediate list.

  ## Why this matters

  LLMs produce filter-then-flat_map pipelines that allocate an intermediate
  list from `Enum.filter` only to immediately consume it with `Enum.flat_map`:

      # Flagged — intermediate list from filter
      numbers
      |> Enum.filter(fn x -> rem(x, 2) == 0 end)
      |> Enum.flat_map(fn x -> [x, x * x] end)

      # Better — single pass, no intermediate list
      numbers
      |> Enum.flat_map(fn x ->
        if rem(x, 2) == 0, do: [x, x * x], else: []
      end)

  `Enum.flat_map` can embed the predicate by returning `[]` for
  non-matching elements, fusing the filter and transform into a single
  traversal without allocating an intermediate list.

  ## Flagged patterns

  `Enum.filter(predicate)` piped into `Enum.flat_map(transform)`.

  ## Not flagged

  - `Enum.filter(pred)` alone (no following `Enum.flat_map`)
  - `Enum.flat_map(transform)` without preceding `Enum.filter`
  - `Enum.filter |> Enum.into` or `Enum.filter |> Enum.map`
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

  # Pipeline: ... |> Enum.filter(pred) |> Enum.flat_map(transform)
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [first, second] ->
      if filter_step?(first) and flat_map_step?(second) do
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

  defp flat_map_step?({{:., _, [mod, :flat_map]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: enum_module?(mod)

  defp flat_map_step?(_), do: false

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp build_issue(filter_node) do
    {{:., dot_meta, [_, :filter]}, _, _} = filter_node

    %Issue{
      rule: :no_filter_then_flat_map,
      message: message(),
      meta: %{line: Keyword.get(dot_meta, :line)}
    }
  end

  defp message do
    "`Enum.filter/2` piped into `Enum.flat_map/2` creates an unnecessary " <>
      "intermediate list. Use `Enum.flat_map` with the predicate embedded " <>
      "(`if pred, do: [...], else: []`) instead."
  end
end
