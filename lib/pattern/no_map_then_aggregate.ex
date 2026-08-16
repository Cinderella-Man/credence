defmodule Credence.Pattern.NoMapThenAggregate do
  @moduledoc """
  Detects `Enum.map/2` immediately followed by `Enum.sum/1`, which creates an
  unnecessary intermediate list, and fuses it into a single `Enum.reduce/3`.

  ## Why this matters

  LLMs default to "transform then aggregate" as the natural functional
  decomposition.  While readable, the intermediate list from `Enum.map`
  is allocated only to be traversed once and discarded:

      # Flagged — two passes, intermediate list allocation
      numbers
      |> Enum.map(&Enum.sum/1)
      |> Enum.sum()

      # Better — single pass, no intermediate list
      numbers
      |> Enum.reduce(0, fn x, acc -> acc + Enum.sum(x) end)

  ## Only `sum` (aggregation), not `max`/`min` (selection)

  Only `Enum.sum/1` is fused. `+` has an identity (`0`) that seeds the reduce,
  and the mapper is applied to every element. `Enum.max/1`/`Enum.min/1` are
  **not** flagged: the natural fusion is `Enum.reduce/2` (no init), whose seed is
  the *first, unmapped* element — so `[5] |> Enum.map(f) |> Enum.max()` would
  give `f.(5)` but the fused `reduce/2` gives the raw `5`. There is no identity
  to seed max/min, so the mapper can't be applied to the seed — the fusion is not
  behaviour-preserving. (Selection-vs-aggregation: same reason `no_explicit_max_reduce`
  was dropped.)

  ## Flagged patterns

  `Enum.map(f)` piped into or wrapping `Enum.sum/1` (pipeline and direct-call forms).

  ## Bad

      defmodule Bad do
        def total(list) do
          Enum.sum(Enum.map(list, fn x -> x * x end))
        end
      end

  ## Good

      defmodule Bad do
        def total(list) do
          Enum.reduce(list, 0, fn el, acc -> acc + el * el end)
        end
      end
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @aggregators [:sum]

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
  def fix_patches(ast, _opts), do: collect_patches(ast)

  #
  # Walks the AST and builds one `Sourceror.patch_string/2` patch per
  # match site (either a pipeline ending in `|> Enum.<agg>` or a
  # direct `Enum.<agg>(Enum.map(...))` nesting). Each patch covers
  # just the byte range of the matched expression, so surrounding
  # source (assignments, blank lines, sibling expressions, comments)
  # stays byte-identical — unlike the previous whole-AST round-trip
  # through `Sourceror.to_string/1`, which Sourceror was free to
  # reformat anywhere.

  defp collect_patches(ast) do
    {_, {patches, _replaced_lines}} =
      Macro.prewalk(ast, {[], MapSet.new()}, fn node, {patches, seen_lines} ->
        line = node_line(node)

        cond do
          line == nil ->
            {node, {patches, seen_lines}}

          MapSet.member?(seen_lines, line) ->
            # Avoid emitting two overlapping patches when a match is
            # nested inside another match's range (e.g. a pipeline
            # whose head is itself a map+agg). Prewalk visits outer
            # first; the inner match's line is already claimed.
            {node, {patches, seen_lines}}

          true ->
            case build_patch(node) do
              {:ok, patch, range_lines} ->
                {node, {[patch | patches], MapSet.union(seen_lines, range_lines)}}

              :skip ->
                {node, {patches, seen_lines}}
            end
        end
      end)

    patches
  end

  defp node_line({_form, meta, _args}) when is_list(meta), do: Keyword.get(meta, :line)
  defp node_line(_), do: nil

  defp build_patch({:|>, _, _} = node) do
    case fix_pipeline(node) do
      nil ->
        :skip

      {map_step, agg_step, reduce_call} ->
        emit_span_patch(node, map_step, agg_step, reduce_call)
    end
  end

  defp build_patch({{:., _, [mod, agg_fn]}, _, [inner]} = node)
       when agg_fn in @aggregators do
    if enum_module?(mod) and map_call?(inner) do
      {_, _, map_fn_args} = inner
      enum_source = hd(map_fn_args)
      map_fn = hd(tl(map_fn_args))
      emit_patch(node, build_reduce(enum_source, map_fn, agg_fn))
    else
      :skip
    end
  end

  defp build_patch(_), do: :skip

  # Patch only the `Enum.map(f) |> Enum.<agg>()` span (map step start → agg step
  # end) with the rendered reduce call — the `|>` before the map step and every
  # other pipeline step are outside the range, so they stay byte-identical. But
  # claim the WHOLE pipeline's lines for dedup so an enclosing `|>` node (visited
  # later by the prewalk, on a different line) does not re-match the same map+agg
  # and emit an overlapping second patch.
  defp emit_span_patch(node, map_step, agg_step, reduce_call) do
    r1 = Sourceror.get_range(map_step)
    r2 = Sourceror.get_range(agg_step)
    range = %{r1 | end: r2.end}
    node_range = Sourceror.get_range(node)
    range_lines = node_range.start[:line]..node_range.end[:line] |> Enum.into(MapSet.new())

    # Render the reduce with the original pipeline's wrap budget so a multi-line
    # pipeline yields a multi-line reduce. Unlike before, only the reduce is
    # rendered (not the whole pipeline), so the budget cannot reformat the
    # untouched before/after steps.
    opts =
      case original_line_budget(node, node_range) do
        nil -> []
        budget -> [line_length: budget]
      end

    {:ok, %{range: range, change: Sourceror.to_string(reduce_call, opts)}, range_lines}
  end

  # Returns the length of the longest line touched by the original
  # expression's range, less the indentation of the first line — i.e.
  # the wrap budget Sourceror should aim for so the replacement looks
  # roughly as long as the original's longest line. `nil` when the
  # original sits on a single line (we keep Sourceror's default).
  defp original_line_budget(_node, range) do
    if range.start[:line] == range.end[:line] do
      nil
    else
      # Conservative budget: just enough to keep `fn args -> body`
      # from collapsing onto one line. A value slightly smaller than
      # the longest expected segment forces the formatter to break at
      # the natural `->` / `|>` points.
      max(range.end[:column] - range.start[:column], 40)
    end
  end

  defp emit_patch(original_node, new_ast) do
    range = Sourceror.get_range(original_node)

    # If the original expression spans multiple source lines, encourage
    # the replacement to also wrap — otherwise Sourceror's default
    # 98-col heuristic collapses short replacements into a single line
    # that visually swallows the structure the user wrote. We compute
    # the longest *body* line of the original and use that as the
    # wrap budget, so a replacement that's shorter than the original's
    # longest line stays compact, and a replacement that's longer wraps.
    opts =
      case original_line_budget(original_node, range) do
        nil -> []
        budget -> [line_length: budget]
      end

    replacement = Sourceror.to_string(new_ast, opts)

    range_lines =
      range.start[:line]..range.end[:line]
      |> Enum.into(MapSet.new())

    {:ok, %{range: range, change: replacement}, range_lines}
  end

  # Returns `{map_step, agg_step, reduce_call}` for the first `… |> Enum.map(f)
  # |> Enum.<agg>()` adjacency, or nil. The caller patches ONLY the span from the
  # map step to the agg step, so the rest of the pipeline (the `before`/`after`
  # steps) stays byte-identical — re-rendering the whole pipeline reformatted
  # unchanged upstream steps (a real over-reach found on a 50-package corpus).
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

        reduce_call =
          if before == [] do
            build_reduce(extract_map_source(first), map_fn, agg_fn)
          else
            build_reduce(nil, map_fn, agg_fn)
          end

        {first, second, reduce_call}
      end
    end)
  end

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

  #
  # `Macro.prewalk/2` rather than hand-written clauses, because earlier
  # versions missed AST shapes where the variable lives in the *form*
  # half of a 3-tuple — most notably remote-call dot access like
  # `c.delivery` parses to `{{:., _, [{:c, _, nil}, :delivery]}, _, []}`
  # and a clause that only maps over `args` never reaches the `:c`.
  defp substitute(body, name, replacement) do
    Macro.prewalk(body, fn
      {^name, _meta, ctx} when is_atom(ctx) -> replacement
      other -> other
    end)
  end

  defp wrap_literal(int) when is_integer(int),
    do: {:__block__, [token: Integer.to_string(int)], [int]}

  # Only the `|>` node where the map step is IMMEDIATELY followed by the
  # aggregator is a fusion site. Scanning the whole flattened pipeline instead
  # re-reported the same `map |> agg` fusion at every downstream `|>` (e.g.
  # `… |> Kernel.+` / `… |> Float.round`), pointing the finding at unrelated steps.
  defp check_node({:|>, meta, [left, right]}) do
    if agg_step?(right) and map_step?(rightmost(left)) do
      {:ok, build_issue(agg_fn_name(right), meta)}
    else
      :error
    end
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

  defp rightmost({:|>, _, [_left, right]}), do: rightmost(right)
  defp rightmost(other), do: other

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
