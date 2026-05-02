defmodule Credence.Rule.NoMapThenAggregate do
  @moduledoc """
  Detects `Enum.map/2` immediately followed by a terminal aggregation
  like `Enum.max/1`, `Enum.min/1`, or `Enum.sum/1`, which creates an
  unnecessary intermediate list.

  ## Why this matters

  LLMs default to "transform then aggregate" as the natural functional
  decomposition.  While readable, the intermediate list from `Enum.map`
  is allocated only to be traversed once and discarded:

      # Flagged — two passes, intermediate list allocation
      numbers
      |> Enum.chunk_every(k, 1, :discard)
      |> Enum.map(&Enum.sum/1)
      |> Enum.max()

      # Better — single pass, no intermediate list
      numbers
      |> Enum.chunk_every(k, 1, :discard)
      |> Enum.reduce(fn chunk, best -> max(Enum.sum(chunk), best) end)

  For `max` and `min`, the fix is `Enum.reduce/2` with `max/2` or
  `min/2`.  For `sum`, the fix is `Enum.reduce/3` accumulating the
  result directly.

  ## Flagged patterns

  `Enum.map(f)` piped into or wrapping:

  - `Enum.max/1`
  - `Enum.min/1`
  - `Enum.sum/1`

  Both pipeline and direct-call nesting forms are detected.
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @aggregators [:max, :min, :sum]

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

  # ------------------------------------------------------------
  # NODE MATCHING
  # ------------------------------------------------------------

  # Pipeline form: ... |> Enum.map(f) |> Enum.max()
  defp check_node({:|>, meta, _} = node) do
    pipeline = flatten_pipeline(node)
    check_pipeline(pipeline, meta)
  end

  # Direct call form: Enum.max(Enum.map(enum, f))
  defp check_node({{:., meta, [mod, agg_fn]}, _, [inner]})
       when agg_fn in @aggregators do
    if enum_module?(mod) and map_call?(inner) do
      {:ok, build_issue(agg_fn, meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # PIPELINE ANALYSIS
  # ------------------------------------------------------------

  defp check_pipeline(steps, meta) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [first, second] ->
      if map_step?(first) and agg_step?(second) do
        {:ok, build_issue(agg_fn_name(second), meta)}
      end
    end)
    |> case do
      {:ok, _} = result -> result
      _ -> :error
    end
  end

  # ------------------------------------------------------------
  # STEP DETECTION
  # ------------------------------------------------------------

  # Enum.map(enum, f) — direct call (2 args)
  defp map_call?({{:., _, [mod, :map]}, _, args})
       when is_list(args) and length(args) == 2 do
    enum_module?(mod)
  end

  defp map_call?(_), do: false

  # Enum.map(f) — pipeline form (1 arg)
  defp map_step?({{:., _, [mod, :map]}, _, args})
       when is_list(args) and length(args) in [1, 2] do
    enum_module?(mod)
  end

  defp map_step?(_), do: false

  # Enum.max/min/sum() — pipeline form (0 args)
  # Enum.max/min/sum(enum) — direct call (1 arg, but handled separately)
  defp agg_step?({{:., _, [mod, fn_name]}, _, args})
       when fn_name in @aggregators and is_list(args) and length(args) in [0, 1] do
    enum_module?(mod)
  end

  defp agg_step?(_), do: false

  defp agg_fn_name({{:., _, [_, fn_name]}, _, _}), do: fn_name

  # ------------------------------------------------------------
  # HELPERS
  # ------------------------------------------------------------

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_issue(agg_fn, meta) do
    %Issue{
      rule: :no_map_then_aggregate,
      message: build_message(agg_fn),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_message(:max) do
    """
    `Enum.map/2` piped into `Enum.max/1` creates an intermediate list.

    Fuse into a single pass:

        Enum.reduce(enumerable, fn x, best -> max(f.(x), best) end)
    """
  end

  defp build_message(:min) do
    """
    `Enum.map/2` piped into `Enum.min/1` creates an intermediate list.

    Fuse into a single pass:

        Enum.reduce(enumerable, fn x, best -> min(f.(x), best) end)
    """
  end

  defp build_message(:sum) do
    """
    `Enum.map/2` piped into `Enum.sum/1` creates an intermediate list.

    Fuse into a single pass:

        Enum.reduce(enumerable, 0, fn x, acc -> acc + f.(x) end)
    """
  end
end
