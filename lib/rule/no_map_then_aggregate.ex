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

  use Credence.Rule

  alias Credence.Issue

  @aggregators [:max, :min, :sum]

  @impl true
  def fixable?, do: true

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
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Pipeline form: ... |> Enum.map(f) |> Enum.max()
      {:|>, _, _} = node ->
        fix_pipeline(node) || node

      # Direct nesting: Enum.max(Enum.map(enum, f))
      {{:., _, [mod, agg_fn]}, _, [inner]} = node
      when agg_fn in @aggregators ->
        if enum_module?(mod) and map_call?(inner) do
          {_, _, map_fn_args} = inner
          enum_source = hd(map_fn_args)
          map_fn = hd(tl(map_fn_args))
          build_reduce(enum_source, map_fn, agg_fn)
        else
          node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  defp fix_pipeline({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[first, second], idx} ->
      if map_step?(first) and agg_step?(second) do
        map_fn = extract_map_fn(first)
        agg_fn = agg_fn_name(second)
        before = Enum.take(steps, idx)
        after_ = Enum.drop(steps, idx + 2)

        reduce_call =
          if before == [] do
            # Map is the first step — extract the source from map's args
            enum_source = extract_map_source(first)
            build_reduce(enum_source, map_fn, agg_fn)
          else
            # Map has a previous step as its source
            nil_reduce = build_reduce(nil, map_fn, agg_fn)
            nil_reduce
          end

        rebuild_pipeline(before, reduce_call, after_)
      end
    end)
  end

  defp build_reduce(source, map_fn, agg_fn) do
    {body_fn, needs_initial} =
      case agg_fn do
        :max ->
          {fn var_el, var_best ->
             {{:., [], [{:__aliases__, [], [:Kernel]}, :max]}, [],
              [apply_call(map_fn, var_el), var_best]}
           end, false}

        :min ->
          {fn var_el, var_best ->
             {{:., [], [{:__aliases__, [], [:Kernel]}, :min]}, [],
              [apply_call(map_fn, var_el), var_best]}
           end, false}

        :sum ->
          {fn var_el, var_acc ->
             {{:., [], [{:__aliases__, [], [:Kernel]}, :+]}, [],
              [var_acc, apply_call(map_fn, var_el)]}
           end, true}
      end

    reduce_fn = reduce_fn_ast(body_fn, needs_initial)

    if needs_initial do
      {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [],
       [source, {:__block__, [], [0]}, reduce_fn]}
    else
      {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [], [source, reduce_fn]}
    end
  end

  defp apply_call(map_fn, var_el) do
    apply_fn = {:apply, [], Elixir}
    {apply_fn, [], [map_fn, {:__block__, [], [var_el]}]}
  end

  defp reduce_fn_ast(body_fn, needs_initial) do
    var_el = {:_el, [], Elixir}
    var_second = if needs_initial, do: {:_acc, [], Elixir}, else: {:_best, [], Elixir}

    body = body_fn.(var_el, var_second)
    {:fn, [], [{:->, [], [[var_el, var_second], body]}]}
  end

  defp check_node({:|>, meta, _} = node) do
    pipeline = flatten_pipeline(node)
    check_pipeline(pipeline, meta)
  end

  defp check_node({{:., meta, [mod, agg_fn]}, _, [inner]})
       when agg_fn in @aggregators do
    if enum_module?(mod) and map_call?(inner) do
      {:ok, build_issue(agg_fn, meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

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

  defp map_call?({{:., _, [mod, :map]}, _, args})
       when is_list(args) and length(args) == 2 do
    enum_module?(mod)
  end

  defp map_call?(_), do: false

  defp map_step?({{:., _, [mod, :map]}, _, args})
       when is_list(args) and length(args) in [1, 2] do
    enum_module?(mod)
  end

  defp map_step?(_), do: false

  defp agg_step?({{:., _, [mod, fn_name]}, _, args})
       when fn_name in @aggregators and is_list(args) and length(args) in [0, 1] do
    enum_module?(mod)
  end

  defp agg_step?(_), do: false

  defp agg_fn_name({{:., _, [_, fn_name]}, _, _}), do: fn_name

  defp extract_map_fn({{:., _, [_, :map]}, _, [_arg]} = step) do
    {{:., _, [_, :map]}, _, [fn_ref]} = step
    fn_ref
  end

  defp extract_map_fn({{:., _, [_, :map]}, _, [_, fn_ref]}), do: fn_ref

  defp extract_map_source({{:., _, [_, :map]}, _, [source, _fn_ref]}), do: source

  defp flatten_pipeline({:|>, _, [left, right]}) do
    flatten_pipeline(left) ++ [right]
  end

  defp flatten_pipeline(expr), do: [expr]

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  defp rebuild_pipeline([], reduce, []) do
    reduce
  end

  defp rebuild_pipeline([], reduce, after_) do
    Enum.reduce(after_, reduce, fn step, acc ->
      {:|>, [], [acc, step]}
    end)
  end

  defp rebuild_pipeline(before, reduce, after_) do
    Enum.reduce(before, fn step, acc ->
      {:|>, [], [acc, step]}
    end)
    |> then(fn pipeline ->
      Enum.reduce(after_, {:|>, [], [pipeline, reduce]}, fn step, acc ->
        {:|>, [], [acc, step]}
      end)
    end)
  end

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
