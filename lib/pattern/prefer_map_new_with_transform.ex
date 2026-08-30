defmodule Credence.Pattern.PreferMapNewWithTransform do
  @moduledoc """
  Detects `Enum.map/2` followed by `Map.new/0` and suggests combining them
  into a single `Map.new/2` call.

  ## Why this matters

  `Enum.map(coll, fn ...) |> Map.new()` allocates an intermediate list of
  2-tuples only to immediately convert them into a map. `Map.new/2` combines
  both steps into a single pass without the intermediate allocation, and is
  clearer about intent.

  ## Bad

      Enum.map(1..5, fn i -> {i, i * i} end) |> Map.new()

      Map.new(Enum.map(1..5, fn i -> {i, i * i} end))

      1..5
      |> Enum.map(fn i -> {i, i * i} end)
      |> Map.new()

  ## Good

      Map.new(1..5, fn i -> {i, i * i} end)

  When the `Enum.map` is fed by an upstream pipeline, that pipeline is kept and
  the map step folds into a piped `Map.new/2` (the collection stays in the pipe):

      # Bad
      list
      |> filter_keys()
      |> Enum.map(fn {k, v} -> {k, f(v)} end)
      |> Map.new()

      # Good
      list
      |> filter_keys()
      |> Map.new(fn {k, v} -> {k, f(v)} end)

  ## Scope

  Flags when ALL of these hold:
  - `Enum.map/2` is called with two arguments (enumerable + function).
  - Its result is passed to `Map.new/0` (via pipe or nesting).
  - The `Map.new` call has zero arguments (i.e., it's `Map.new/0`, not `Map.new/1`).

  Does NOT flag:
  - `Enum.map/2` alone (no following `Map.new`).
  - `Map.new/1` (with an explicit enumerable arg).
  - `Enum.map/2` with a function that doesn't return 2-tuples (we don't check this —
    the pattern match is syntactic only).

  ## Auto-fix

  Replaces the `Enum.map |> Map.new` pair with `Map.new/2`, moving the
  enumerable and function into the `Map.new` call.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    if shadows_core_module?(ast) do
      []
    else
      {_ast, issues} =
        Macro.prewalk(ast, [], fn node, issues ->
          case check_node(node) do
            {:ok, issue} -> {node, [issue | issues]}
            :error -> {node, issues}
          end
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    if shadows_core_module?(ast) do
      []
    else
      RuleHelpers.patches_from_postwalk(ast, fn node ->
        case transform_node(node) do
          {:ok, new_ast} -> new_ast
          _ -> node
        end
      end)
    end
  end

  # Bare `Enum` and `Map` calls are only known to be the standard modules when
  # neither name is replaced by an alias. Alias scope is lexical, so conservatively
  # leave the whole file alone if either name is shadowed anywhere in it.
  defp shadows_core_module?(ast) do
    {_ast, shadowed?} =
      Macro.prewalk(ast, false, fn
        {:alias, _, args} = node, false -> {node, shadowing_alias?(args)}
        node, acc -> {node, acc}
      end)

    shadowed?
  end

  defp shadowing_alias?([target, opts]) when is_list(opts) do
    case alias_as(opts) do
      nil -> aliases_core_name?(target)
      as -> aliases_core_name?(as)
    end
  end

  defp shadowing_alias?([target]), do: aliases_core_name?(target)
  defp shadowing_alias?(_), do: false

  defp alias_as(opts) do
    Enum.find_value(opts, fn
      {:as, value} -> value
      {{:__block__, _, [:as]}, value} -> value
      _ -> nil
    end)
  end

  defp aliases_core_name?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _, parts} = node, false -> {node, List.last(parts) in [:Enum, :Map]}
        node, acc -> {node, acc}
      end)

    found?
  end

  # --- check ---

  # Pipe: ... |> Enum.map(fn ...) |> Map.new()
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[first, second], idx} ->
      if fixable_pair?(first, second, idx) do
        {:ok, build_issue(first)}
      end
    end)
    |> case do
      {:ok, _} = result -> result
      _ -> :error
    end
  end

  # Nested: Map.new(Enum.map(coll, fn ...))
  defp check_node(
         {{:., _, [{:__aliases__, _, [:Map]}, :new]}, meta,
          [{{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_coll, _fn_arg]}]}
       ) do
    {:ok, build_issue(meta)}
  end

  defp check_node(_), do: :error

  # --- transform ---

  # Pipe: ... |> Enum.map(fn ...) |> Map.new()
  defp transform_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[first, second], idx} ->
      if map_step?(first) and map_new_empty_step?(second) do
        case build_map_new_pipeline(steps, first, idx) do
          nil -> nil
          pipeline -> {:ok, pipeline}
        end
      end
    end)
  end

  # Nested: Map.new(Enum.map(coll, fn ...))
  defp transform_node(
         {{:., _, [{:__aliases__, _, [:Map]}, :new]}, _meta,
          [{{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [coll, fn_arg]}]}
       ) do
    {:ok, build_map_new_call(coll, fn_arg)}
  end

  defp transform_node(_), do: :error

  # Build the replacement pipeline for the `Enum.map(...) |> Map.new/MapSet.new`
  # window found at `idx`, or nil when the shape can't be rewritten safely. Split
  # out of `transform_node/1` to keep the pipe-walking callback shallow.
  defp build_map_new_pipeline(steps, first, idx) do
    {coll, fn_arg} = extract_map_parts(first)
    before = Enum.take(steps, idx)
    after_ = Enum.drop(steps, idx + 2)

    cond do
      coll != nil ->
        # 2-arg Enum.map: Enum.map(coll, fn ...) — coll is explicit
        map_new_call = build_map_new_call(coll, fn_arg)

        if before == [] and after_ == [] do
          map_new_call
        else
          rebuild_pipeline(before, map_new_call, after_)
        end

      before != [] ->
        # 1-arg Enum.map in pipeline context: ... |> Enum.map(fn ...)
        case before do
          [coll] ->
            # The collection IS the pipe head (a complete expression), so
            # inline it as `Map.new/2`'s first argument.
            map_new_call = build_map_new_call(coll, fn_arg)
            if after_ == [], do: map_new_call, else: rebuild_pipeline([], map_new_call, after_)

          _ ->
            # There is an upstream pipeline before `Enum.map`. Its last step
            # is itself a pipe stage missing its piped input, so it must NOT
            # be pulled out as an explicit collection (that loses the input
            # and produces `Map.new/3`). Instead keep the whole upstream
            # pipeline intact and pipe it into a 1-arg `Map.new(fn)` — which
            # in pipe position is exactly `Map.new/2`.
            map_new_step = build_map_new_fn_step(fn_arg)
            rebuild_pipeline(before, map_new_step, after_)
        end

      true ->
        nil
    end
  end

  # --- predicates ---

  # A pipe pair is fixable when the second step is `Map.new/0` and the first is an
  # `Enum.map` whose collection the fix can recover. The 2-arg form carries its own
  # collection; the 1-arg form (pipe context) needs a preceding step to supply it,
  # which only exists when this pair isn't at the head of the pipeline (idx > 0).
  # This mirrors `transform_node/1` exactly so check and fix never disagree.
  defp fixable_pair?(first, second, idx) do
    map_new_empty_step?(second) and fixable_map_step?(first, idx)
  end

  defp fixable_map_step?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_, _]}, _idx), do: true

  defp fixable_map_step?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_]}, idx), do: idx > 0

  defp fixable_map_step?(_, _), do: false

  # 2-arg form: Enum.map(coll, fn ...)
  defp map_step?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_, _]}), do: true
  # 1-arg form (pipe context): Enum.map(fn ...)
  defp map_step?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [_]}), do: true
  defp map_step?(_), do: false

  defp map_new_empty_step?({{:., _, [{:__aliases__, _, [:Map]}, :new]}, _, []}), do: true
  defp map_new_empty_step?(_), do: false

  # --- extraction helpers ---

  # 2-arg form: Enum.map(coll, fn ...)
  defp extract_map_parts({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [coll, fn_arg]}) do
    {coll, fn_arg}
  end

  # 1-arg form (pipe context): Enum.map(fn ...)
  defp extract_map_parts({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [fn_arg]}) do
    {nil, fn_arg}
  end

  # --- AST builders ---

  defp build_map_new_call(coll, fn_arg) do
    {{:., [], [{:__aliases__, [], [:Map]}, :new]}, [], [coll, fn_arg]}
  end

  # 1-arg `Map.new(fn)` — only ever emitted as a pipe step, where the piped
  # collection supplies the first argument, making it `Map.new/2`.
  defp build_map_new_fn_step(fn_arg) do
    {{:., [], [{:__aliases__, [], [:Map]}, :new]}, [], [fn_arg]}
  end

  # --- pipeline helpers ---

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(expr), do: [expr]

  defp rebuild_pipeline([], step, []), do: step

  defp rebuild_pipeline([], step, after_) do
    Enum.reduce(after_, step, fn s, acc -> {:|>, [], [acc, s]} end)
  end

  defp rebuild_pipeline(before, step, after_) do
    pipeline =
      before
      |> Enum.reduce(fn s, acc -> {:|>, [], [acc, s]} end)
      |> then(fn head -> {:|>, [], [head, step]} end)

    Enum.reduce(after_, pipeline, fn s, acc -> {:|>, [], [acc, s]} end)
  end

  # --- issue builder ---

  # Accepts either a metadata keyword list (nested form passes the `Map.new`
  # call's meta) or a whole AST node (the pipe form passes the `Enum.map` step);
  # `get_line/1` resolves a `:line` from either.
  defp build_issue(node_or_meta) do
    %Issue{
      rule: :prefer_map_new_with_transform,
      message:
        "`Enum.map/2` followed by `Map.new/0` allocates an intermediate list. Use `Map.new/2` instead for a single-pass conversion.",
      meta: %{line: get_line(node_or_meta)}
    }
  end

  defp get_line(meta) when is_list(meta), do: Keyword.get(meta, :line)
  defp get_line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line)
  defp get_line(_), do: nil
end
