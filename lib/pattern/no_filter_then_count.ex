defmodule Credence.Pattern.NoFilterThenCount do
  @moduledoc """
  Detects `Enum.filter/2` piped into `length/1` or `Enum.count/1`, which
  creates an unnecessary intermediate list.

  ## Why this matters

  `Enum.filter/2` produces a new list, then `length/1` (or `Enum.count/1`)
  traverses it to count elements. `Enum.count/2` with a predicate does both
  in a single pass without allocating the intermediate list:

      # Flagged — allocates intermediate list
      numbers
      |> Enum.filter(fn x -> rem(x, 2) == 0 end)
      |> length()

      # Better — single pass, no intermediate list
      Enum.count(numbers, fn x -> rem(x, 2) == 0 end)

  ## Flagged patterns

  - `Enum.filter(predicate)` piped into `length/1` or `Enum.count/1`
  - `length(Enum.filter(enum, predicate))`
  - `Enum.count(Enum.filter(enum, predicate))`

  ## Not flagged

  - `Enum.filter(pred)` alone (no following count/length)
  - `Enum.count(enum, pred)` (already idiomatic)
  - `length(enum)` without preceding filter

  ## Bad

      defmodule BadNFTC do
        def count_positives(items) do
          items
          |> Enum.filter(&(&1 > 0))
          |> length()
        end
      end

  ## Good

      defmodule BadNFTC do
        def count_positives(items) do
          items |> Enum.count(&(&1 > 0))
        end
      end
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
  def fix_patches(ast, _opts) do
    {_, patches} =
      Macro.prewalk(ast, [], fn node, patches ->
        case build_patch(node) do
          {:ok, patch} -> {node, [patch | patches]}
          :skip -> {node, patches}
        end
      end)

    patches
  end

  # ── Patch builders ────────────────────────────────────────────────────

  # Pipeline: ... |> Enum.filter(pred) |> length() / |> Enum.count()
  defp build_patch({:|>, _, _} = node) do
    case fix_pipeline(node) do
      nil -> :skip
      {new_ast, original_range} -> emit_patch(original_range, new_ast)
    end
  end

  # Nested: length(Enum.filter(enum, pred))
  defp build_patch(
         {:length, _, [{{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, [enum, pred]}]} =
           node
       ) do
    count_call = make_count_call(enum, pred)
    emit_patch_from_node(node, count_call)
  end

  # Nested: Enum.count(Enum.filter(enum, pred))
  defp build_patch(
         {{:., _, [{:__aliases__, _, [:Enum]}, :count]}, _,
          [{{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, [enum, pred]}]} =
           node
       ) do
    count_call = make_count_call(enum, pred)
    emit_patch_from_node(node, count_call)
  end

  defp build_patch(_), do: :skip

  defp fix_pipeline({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[first, second], idx} ->
      if filter_step?(first) and count_terminal?(second) do
        {coll, pred} = extract_filter_parts(first)
        before = Enum.take(steps, idx)
        after_ = Enum.drop(steps, idx + 2)

        count_step = make_count_call(coll, pred)

        pipeline = rebuild_pipeline(before, count_step, after_)

        if pipeline, do: {pipeline, Sourceror.get_range(node)}
      end
    end)
  end

  defp extract_filter_parts({{:., _, [_, :filter]}, _, [pred]}), do: {nil, pred}
  defp extract_filter_parts({{:., _, [_, :filter]}, _, [coll, pred]}), do: {coll, pred}

  defp make_count_call(nil, pred) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :count]}, [], [pred]}
  end

  defp make_count_call(coll, pred) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :count]}, [], [coll, pred]}
  end

  defp emit_patch(%Sourceror.Range{} = range, new_ast) do
    replacement = Sourceror.to_string(new_ast)
    {:ok, %{range: range, change: replacement}}
  end

  defp emit_patch(_, _), do: :skip

  defp emit_patch_from_node(original_node, new_ast) do
    case Sourceror.get_range(original_node) do
      %Sourceror.Range{} = range ->
        replacement = Sourceror.to_string(new_ast)
        {:ok, %{range: range, change: replacement}}

      _ ->
        :skip
    end
  end

  # ── Check ─────────────────────────────────────────────────────────────

  # Pipeline: ... |> Enum.filter(pred) |> length() / |> Enum.count()
  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [first, second] ->
      if filter_step?(first) and count_terminal?(second) do
        {:ok, build_issue(first)}
      end
    end)
    |> case do
      {:ok, _} = result -> result
      _ -> :error
    end
  end

  # Nested: length(Enum.filter(enum, pred)) — only the 2-arg filter the fix rewrites
  defp check_node({:length, meta, [{{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, [_, _]}]}) do
    {:ok, build_issue_from_meta(meta)}
  end

  # Nested: Enum.count(Enum.filter(enum, pred)) — only the 2-arg filter the fix rewrites
  defp check_node(
         {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _,
          [{{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, [_, _]}]}
       ) do
    {:ok, build_issue_from_meta(meta)}
  end

  defp check_node(_), do: :error

  # ── Predicates ────────────────────────────────────────────────────────

  defp filter_step?({{:., _, [mod, :filter]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: enum_module?(mod)

  defp filter_step?(_), do: false

  defp count_terminal?({:length, _, []}), do: true

  defp count_terminal?({{:., _, [mod, :count]}, _, []}), do: enum_module?(mod)

  defp count_terminal?(_), do: false

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?(_), do: false

  # ── Issue builders ────────────────────────────────────────────────────

  defp build_issue(filter_node) do
    {{:., meta, [_, :filter]}, _, _} = filter_node

    %Issue{
      rule: :no_filter_then_count,
      message: message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue_from_meta(meta) do
    %Issue{
      rule: :no_filter_then_count,
      message: message(),
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp message do
    "`Enum.filter/2` piped into `length/1` or `Enum.count/1` creates an " <>
      "unnecessary intermediate list. Use `Enum.count/2` with a predicate instead."
  end

  # ── Pipeline utilities ────────────────────────────────────────────────

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
end
