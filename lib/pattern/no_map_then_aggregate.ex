defmodule Credence.Pattern.NoMapThenAggregate do
  @moduledoc """
  Detects `Enum.map/2` immediately followed by `Enum.max_by/2`,
  `Enum.min_by/2`, or a collection constructor like `MapSet.new/1`
  or `Map.new/1`, which creates an unnecessary intermediate list.

  ## Why this matters

  LLMs default to "transform then aggregate" as the natural functional
  decomposition.  While readable, the intermediate list from `Enum.map`
  is allocated only to be traversed once and discarded:

      # Flagged — intermediate list, can use MapSet.new/2 directly
      items
      |> Enum.map(fn {_, v} -> v end)
      |> MapSet.new()

      # Better — single call with transform
      MapSet.new(items, fn {_, v} -> v end)

  `Enum.map/2` piped into `Enum.max/1`, `Enum.min/1`, or `Enum.sum/1`
  is **not** flagged — those are idiomatic Elixir patterns with no
  cleaner alternative (`Enum.reduce` has no safe initial value for
  max/min, and `Enum.map |> Enum.sum` clearly separates transformation
  from aggregation).

  ## Flagged patterns

  `Enum.map(f)` piped into or wrapping:
  - `Enum.max_by/2` / `Enum.min_by/2` (check-only)
  - `MapSet.new/1`
  - `Map.new/1`

  Both pipeline and direct-call nesting forms are detected.
  """

  use Credence.Pattern.Rule

  alias Credence.Issue

  @aggregators [:max_by, :min_by]
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

  # max_by/min_by: check-only (no auto-fix) — the fused reduce would
  # change the return type (original element vs mapped element).
  defp build_patch({{:., _, [_mod, agg_fn]}, _, [_inner]})
       when agg_fn in @aggregators do
    :skip
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
          # max_by/min_by: check-only (no auto-fix) — the fused reduce
          # would change the return type (original element vs mapped element).
          nil

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

  defp build_constructor_ast(source, map_fn, mod) do
    args = if source, do: [source, map_fn], else: [map_fn]
    {{:., [], [mod, :new]}, [], args}
  end

  defp check_node({:|>, meta, _} = node) do
    pipeline = flatten_pipeline(node)
    check_pipeline(pipeline, meta)
  end

  # 2-arg form: Enum.max_by(Enum.map(enum, f), g) / Enum.min_by(…)
  defp check_node({{:., meta, [mod, agg_fn]}, _, [inner, _selector]})
       when agg_fn in [:max_by, :min_by] do
    if enum_module?(mod) and map_call?(inner) do
      {:ok, build_issue(agg_fn, meta)}
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

  defp build_message(:max_by),
    do:
      "`Enum.map/2` piped into `Enum.max_by/2` creates an intermediate list. Use `Enum.max_by/2` directly on the source enumerable instead."

  defp build_message(:min_by),
    do:
      "`Enum.map/2` piped into `Enum.min_by/2` creates an intermediate list. Use `Enum.min_by/2` directly on the source enumerable instead."

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
