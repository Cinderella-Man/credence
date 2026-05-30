defmodule Credence.Pattern.NoMapThenAggregate do
  @moduledoc """
  Detects `Enum.map/2` immediately followed by a terminal aggregation
  like `Enum.max/1`, `Enum.min/1`, `Enum.sum/1`, or a collection
  constructor like `MapSet.new/1` or `Map.new/1`, which creates an
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
  - `MapSet.new/1`
  - `Map.new/1`

  Both pipeline and direct-call nesting forms are detected.
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @aggregators [:max, :min, :sum]
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

      new_ast ->
        emit_patch(node, new_ast)
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

  defp build_patch({{:., _, [mod, :new]}, _, [inner]} = node) do
    if constructor_module?(mod) and map_call?(inner) do
      {_, _, map_fn_args} = inner
      enum_source = hd(map_fn_args)
      map_fn = hd(tl(map_fn_args))
      emit_patch(node, build_constructor_ast(enum_source, map_fn, mod))
    else
      :skip
    end
  end

  defp build_patch(_), do: :skip

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

  defp fix_pipeline({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[first, second], idx} ->
      cond do
        map_step?(first) and agg_step?(second) ->
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

        map_step?(first) and constructor_step?(second) ->
          map_fn = extract_map_fn(first)
          constructor_mod = extract_constructor_mod(second)
          before = Enum.take(steps, idx)
          after_ = Enum.drop(steps, idx + 2)

          constructor_call =
            if before == [] do
              enum_source = extract_map_source(first)
              build_constructor_ast(enum_source, map_fn, constructor_mod)
            else
              build_constructor_ast(nil, map_fn, constructor_mod)
            end

          rebuild_pipeline(before, constructor_call, after_)

        true ->
          nil
      end
    end)
  end

  defp build_reduce(source, map_fn, agg_fn) do
    {param, mapped_expr} = resolve_map_fn(map_fn)

    case agg_fn do
      :sum ->
        acc_var = {:acc, [], Elixir}
        body = {:+, [], [acc_var, mapped_expr]}
        reduce_fn = {:fn, [], [{:->, [], [[param, acc_var], body]}]}

        args =
          if source do
            [source, wrap_literal(0), reduce_fn]
          else
            [wrap_literal(0), reduce_fn]
          end

        {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [], args}

      agg when agg in [:max, :min] ->
        best_var = {:best, [], Elixir}
        body = {agg, [], [mapped_expr, best_var]}
        reduce_fn = {:fn, [], [{:->, [], [[param, best_var], body]}]}

        args = if source, do: [source, reduce_fn], else: [reduce_fn]

        {{:., [], [{:__aliases__, [], [:Enum]}, :reduce]}, [], args}
    end
  end

  defp build_constructor_ast(source, map_fn, mod) do
    args = if source, do: [source, map_fn], else: [map_fn]
    {{:., [], [mod, :new]}, [], args}
  end

  # Extracts the reduce parameter and mapped expression from the map function.
  #
  # For simple variable lambdas (fn x -> x * 2 end), substitutes the variable
  # with `el` and uses `el` as the reduce parameter.
  #
  # For destructuring lambdas (fn {a, b} -> body end), uses the pattern directly
  # as the reduce parameter — avoids generating `(fn {a, b} -> ... end).(el)`.

  # fn x -> body end (simple variable) → {el, body[x := el]}
  defp resolve_map_fn({:fn, _, [{:->, _, [[{param, _, ctx}], body]}]})
       when is_atom(param) and is_atom(ctx) do
    el_var = {:el, [], Elixir}
    {el_var, substitute(body, param, el_var)}
  end

  # fn pattern -> body end (destructuring) → {pattern, body}
  defp resolve_map_fn({:fn, _, [{:->, _, [patterns, body]}]})
       when is_list(patterns) and length(patterns) == 1 do
    [pattern] = patterns
    {pattern, body}
  end

  # &Mod.fun/1, &fun/1, etc. → {el, Mod.fun(el)} via inline_call
  defp resolve_map_fn(map_fn) do
    el_var = {:el, [], Elixir}
    {el_var, inline_call(map_fn, el_var)}
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

  defp check_node({{:., meta, [mod, :new]}, _, [inner]}) do
    if constructor_module?(mod) and map_call?(inner) do
      {:ok, build_constructor_issue_from_mod(mod, meta)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  defp check_pipeline(steps, meta) do
    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [first, second] ->
      cond do
        map_step?(first) and agg_step?(second) ->
          {:ok, build_issue(agg_fn_name(second), meta)}

        map_step?(first) and constructor_step?(second) ->
          {:ok, build_constructor_issue(second, meta)}

        true ->
          nil
      end
    end)
    |> case do
      {:ok, _} = result -> result
      _ -> :error
    end
  end

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

  defp constructor_module?({:__aliases__, _, [mod]}) when mod in @constructor_modules, do: true
  defp constructor_module?(_), do: false

  defp constructor_step?({{:., _, [mod, :new]}, _, args})
       when is_list(args) and length(args) in [0, 1],
       do: constructor_module?(mod)

  defp constructor_step?(_), do: false

  defp extract_constructor_mod({{:., _, [mod, :new]}, _, _}), do: mod

  defp extract_map_fn({{:., _, [_, :map]}, _, [fn_ref]}), do: fn_ref
  defp extract_map_fn({{:., _, [_, :map]}, _, [_, fn_ref]}), do: fn_ref

  defp extract_map_source({{:., _, [_, :map]}, _, [source, _fn_ref]}), do: source

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

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

  defp build_constructor_issue(step, meta) do
    mod = extract_constructor_mod(step)
    build_constructor_issue_from_mod(mod, meta)
  end

  defp build_constructor_issue_from_mod(mod, meta) do
    {:__aliases__, _, [mod_name]} = mod

    %Issue{
      rule: :no_map_then_aggregate,
      message:
        "`Enum.map/2` piped into `#{mod_name}.new/1` creates an intermediate list. Use `#{mod_name}.new(enum, transform)` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
