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
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn node ->
      case transform_node(node) do
        {:ok, new_ast} -> new_ast
        _ -> node
      end
    end)
  end

  # --- check ---

  # Pipe: ... |> Enum.map(fn ...) |> Map.new()
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn
      [first, second] ->
        if map_step?(first) and map_new_empty_step?(second) do
          {:ok, build_issue(first)}
        end

      _ ->
        nil
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
        {coll, fn_arg} = extract_map_parts(first)
        before = Enum.take(steps, idx)
        after_ = Enum.drop(steps, idx + 2)

        pipeline =
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
              # Extract the collection from the pipe and pass it directly
              coll_from_pipe = List.last(before)
              remaining_before = Enum.drop(before, -1)
              map_new_call = build_map_new_call(coll_from_pipe, fn_arg)

              if remaining_before == [] and after_ == [] do
                map_new_call
              else
                rebuild_pipeline(remaining_before, map_new_call, after_)
              end

            true ->
              nil
          end

        if pipeline, do: {:ok, pipeline}
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

  # --- predicates ---

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
