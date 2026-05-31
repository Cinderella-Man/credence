defmodule Credence.Pattern.NoFilterThenNew do
  @moduledoc """
  Detects `Enum.filter/2` piped into `MapSet.new/2` or `Map.new/2` with a
  transform function, which creates an unnecessary intermediate list.

  ## Why this matters

  LLMs produce filter-then-collect pipelines that allocate an intermediate
  list from `Enum.filter` only to immediately consume it:

      # Flagged — intermediate list from filter
      freq_map
      |> Enum.filter(fn {_char, count} -> count == max_freq end)
      |> MapSet.new(fn {char, _count} -> char end)

      # Better — single pass, no intermediate list
      for {char, count} <- freq_map, count == max_freq, into: MapSet.new(), do: char

  A `for` comprehension with a guard and `:into` fuses the filter and
  transform into a single traversal.

  ## Flagged patterns

  `Enum.filter(predicate)` piped into:
  - `MapSet.new(transform)`
  - `Map.new(transform)`

  Only the two-argument form (with transform function) is flagged.
  `Enum.filter |> MapSet.new()` (no transform) is fine — it may be
  intentional to keep the filtered elements as-is.
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @constructor_modules [:MapSet, :Map]

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

  # Pipeline: ... |> Enum.filter(pred) |> MapSet.new(fn)
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [first, second] ->
      if filter_step?(first) and constructor_with_fn_step?(second) do
        {:ok, build_issue(first, second)}
      else
        nil
      end
    end)
    |> case do
      {:ok, _} = result -> result
      _ -> :error
    end
  end

  # Nested: MapSet.new(Enum.filter(enum, pred), fn)
  defp check_node({{:., _, [mod, :new]}, meta, [filter_call, _fn]} = _node) do
    if constructor_module?(mod) and filter_call?(filter_call) do
      {:ok, build_issue_from_nested(meta, mod)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  defp filter_step?({{:., _, [mod, :filter]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: enum_module?(mod)

  defp filter_step?(_), do: false

  defp filter_call?({{:., _, [mod, :filter]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: enum_module?(mod)

  defp filter_call?(_), do: false

  # In pipeline context, MapSet.new(fn) has 1 explicit arg (the transform fn)
  defp constructor_with_fn_step?({{:., _, [mod, :new]}, _, [fn_node]}),
    do: constructor_module?(mod) and fn_node?(fn_node)

  defp constructor_with_fn_step?(_), do: false

  defp fn_node?({:fn, _, _}), do: true
  defp fn_node?({:&, _, _}), do: true
  defp fn_node?(_), do: false

  defp constructor_module?({:__aliases__, _, [mod]}) when mod in @constructor_modules, do: true
  defp constructor_module?(_), do: false

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp build_issue(filter_node, constructor_node) do
    {{:., meta, [_, :filter]}, _, _} = filter_node
    {{:., _, [mod, :new]}, _, _} = constructor_node
    {:__aliases__, _, [mod_name]} = mod

    %Issue{
      rule: :no_filter_then_new,
      message: message(mod_name),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue_from_nested(meta, mod) do
    {:__aliases__, _, [mod_name]} = mod

    %Issue{
      rule: :no_filter_then_new,
      message: message(mod_name),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp message(mod_name) do
    "`Enum.filter/2` piped into `#{mod_name}.new/2` creates an unnecessary " <>
      "intermediate list. Use `for x <- enum, pred.(x), into: #{mod_name}.new(), " <>
      "do: transform.(x)` instead."
  end
end
