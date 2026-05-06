defmodule Credence.Pattern.NoMapThenAggregate do
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

  # ── Pipeline fix ────────────────────────────────────────────────

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
            enum_source = extract_map_source(first)
            build_reduce(enum_source, map_fn, agg_fn)
          else
            build_reduce(nil, map_fn, agg_fn)
          end

        rebuild_pipeline(before, reduce_call, after_)
      end
    end)
  end

  # ── Build the reduce replacement ────────────────────────────────

  defp build_reduce(source, map_fn, agg_fn) do
    el_var = {:el, [], Elixir}

    case agg_fn do
      :sum ->
        acc_var = {:acc, [], Elixir}
        body = {:+, [], [acc_var, inline_call(map_fn, el_var)]}
        reduce_fn = {:fn, [], [{:->, [], [[el_var, acc_var], body]}]}

        args =
          if source do
            [source, wrap_literal(0), reduce_fn]
          else
            [wrap_literal(0), reduce_fn]
          end

        {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [], args}

      agg when agg in [:max, :min] ->
        best_var = {:best, [], Elixir}
        body = {agg, [], [inline_call(map_fn, el_var), best_var]}
        reduce_fn = {:fn, [], [{:->, [], [[el_var, best_var], body]}]}

        args = if source, do: [source, reduce_fn], else: [reduce_fn]

        {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [], args}
    end
  end

  # ── Inline a map function applied to a variable ─────────────────
  #
  # Instead of generating `apply(fn, el)` or `fn.(el)`, we inline
  # the function call directly:
  #
  #   &String.length/1  → String.length(el)
  #   &byte_size/1      → byte_size(el)
  #   fn w -> w * 2 end → el * 2
  #   & &1.price        → el.price    (falls back to capture call)

  # Remote capture: &Mod.fun/arity → Mod.fun(el)
  defp inline_call(
         {:&, _,
          [
            {:/, _,
             [
               {{:., _, [mod, fun]}, _, []},
               _arity
             ]}
          ]},
         var
       ) do
    {{:., [], [mod, fun]}, [], [var]}
  end

  # Remote capture with __block__-wrapped arity (Sourceror form)
  defp inline_call(
         {:&, _,
          [
            {:/, _,
             [
               {{:., _, [mod, fun]}, _, []},
               {:__block__, _, [_arity]}
             ]}
          ]},
         var
       ) do
    {{:., [], [mod, fun]}, [], [var]}
  end

  # Local capture: &fun/arity → fun(el)
  defp inline_call(
         {:&, _, [{:/, _, [{fun, _, _}, _arity]}]},
         var
       )
       when is_atom(fun) do
    {fun, [], [var]}
  end

  # Anonymous function: fn param -> body end → substitute param with el
  defp inline_call(
         {:fn, _, [{:->, _, [[{param, _, ctx}], body]}]},
         var
       )
       when is_atom(param) and is_atom(ctx) do
    substitute(body, param, var)
  end

  # Fallback: f.(el)
  defp inline_call(map_fn, var) do
    {{:., [], [map_fn]}, [], [var]}
  end

  # ── Variable substitution ───────────────────────────────────────

  defp substitute({name, _meta, ctx}, name, replacement) when is_atom(ctx),
    do: replacement

  defp substitute({form, meta, args}, name, replacement) when is_list(args),
    do: {form, meta, Enum.map(args, &substitute(&1, name, replacement))}

  defp substitute({left, right}, name, replacement),
    do: {substitute(left, name, replacement), substitute(right, name, replacement)}

  defp substitute(list, name, replacement) when is_list(list),
    do: Enum.map(list, &substitute(&1, name, replacement))

  defp substitute(other, _, _), do: other

  # ── Literal wrapping (Sourceror compat) ─────────────────────────

  defp wrap_literal(int) when is_integer(int),
    do: {:__block__, [token: Integer.to_string(int)], [int]}

  # ── Check helpers ───────────────────────────────────────────────

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

  # ── AST matchers ────────────────────────────────────────────────

  defp map_call?({{:., _, [mod, :map]}, _, args})
       when is_list(args) and length(args) == 2,
       do: enum_module?(mod)

  defp map_call?(_), do: false

  defp map_step?({{:., _, [mod, :map]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: enum_module?(mod)

  defp map_step?(_), do: false

  defp agg_step?({{:., _, [mod, fn_name]}, _, args})
       when fn_name in @aggregators and is_list(args) and length(args) in [0, 1],
       do: enum_module?(mod)

  defp agg_step?(_), do: false

  defp agg_fn_name({{:., _, [_, fn_name]}, _, _}), do: fn_name

  defp extract_map_fn({{:., _, [_, :map]}, _, [fn_ref]}), do: fn_ref
  defp extract_map_fn({{:., _, [_, :map]}, _, [_, fn_ref]}), do: fn_ref

  defp extract_map_source({{:., _, [_, :map]}, _, [source, _fn_ref]}), do: source

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  # ── Pipeline rebuilding ─────────────────────────────────────────

  defp rebuild_pipeline([], reduce, []), do: reduce

  defp rebuild_pipeline([], reduce, after_) do
    Enum.reduce(after_, reduce, fn step, acc -> {:|>, [], [acc, step]} end)
  end

  defp rebuild_pipeline(before, reduce, after_) do
    Enum.reduce(before, fn step, acc -> {:|>, [], [acc, step]} end)
    |> then(fn pipeline ->
      Enum.reduce(after_, {:|>, [], [pipeline, reduce]}, fn step, acc ->
        {:|>, [], [acc, step]}
      end)
    end)
  end

  # ── Issue building ──────────────────────────────────────────────

  defp build_issue(agg_fn, meta) do
    %Issue{
      rule: :no_map_then_aggregate,
      message: build_message(agg_fn),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_message(:max),
    do:
      "`Enum.map/2` piped into `Enum.max/1` creates an intermediate list. Fuse into `Enum.reduce(enum, fn el, best -> max(f(el), best) end)`."

  defp build_message(:min),
    do:
      "`Enum.map/2` piped into `Enum.min/1` creates an intermediate list. Fuse into `Enum.reduce(enum, fn el, best -> min(f(el), best) end)`."

  defp build_message(:sum),
    do:
      "`Enum.map/2` piped into `Enum.sum/1` creates an intermediate list. Fuse into `Enum.reduce(enum, 0, fn el, acc -> acc + f(el) end)`."
end
