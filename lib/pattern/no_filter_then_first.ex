defmodule Credence.Pattern.NoFilterThenFirst do
  @moduledoc """
  Performance rule (fixable): Detects `Stream.filter/2` piped into `Enum.at/2`
  with a literal `0` index.

  `Stream.filter` is lazy, so `Stream.filter(coll, pred) |> Enum.at(0)`
  evaluates `pred` only until the first match — exactly what `Enum.find/2`
  does. The rewrite is behaviour-preserving, including the number of predicate
  evaluations (so side-effecting or raising predicates behave identically).

  The eager `Enum.filter/2` form is deliberately **not** flagged: it evaluates
  `pred` on every element, whereas `Enum.find/2` stops at the first match. With
  a side-effecting or raising predicate the two diverge (e.g. a predicate that
  raises on a later element crashes the `Enum.filter` form but not the
  `Enum.find` rewrite), so the rewrite would not give the same answer.

  ## Flagged

      Stream.filter(numbers, &(&1 > 10)) |> Enum.at(0)
      Enum.at(Stream.filter(numbers, &(&1 > 10)), 0)

  ## Not flagged

      Enum.filter(numbers, &(&1 > 10)) |> Enum.at(0)   # eager: changes pred evaluation
      Stream.filter(numbers, &(&1 > 10)) |> Enum.at(1) # not index 0
      Stream.filter(numbers, &(&1 > 10)) |> Enum.at(0, -1) # has default arg
      Enum.find(numbers, &(&1 > 10))                    # already idiomatic
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

  # Pipeline: ... |> Enum.filter(pred) |> Enum.at(0)
  defp build_patch({:|>, _, _} = node) do
    case fix_pipeline(node) do
      nil -> :skip
      {new_ast, original_range} -> emit_patch(original_range, new_ast)
    end
  end

  # Nested: Enum.at(Stream.filter(coll, pred), 0)
  defp build_patch(
         {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _,
          [{{:., _, [{:__aliases__, _, [mod]}, :filter]}, _, [coll, pred]}, {:__block__, _, [0]}]}
         = node
       )
       when mod == :Stream do
    find_call = make_find_call(coll, pred)
    emit_patch_from_node(node, find_call)
  end

  defp build_patch(_), do: :skip

  defp fix_pipeline({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[first, second], idx} ->
      if filter_step?(first) and at_zero_step?(second) do
        {coll, pred} = extract_filter_parts(first)
        before = Enum.take(steps, idx)
        after_ = Enum.drop(steps, idx + 2)

        find_step = make_find_call(coll, pred)

        pipeline =
          cond do
            coll != nil ->
              # 2-arg filter: Enum.filter(coll, pred) — coll is explicit
              if before == [] and after_ == [] do
                find_step
              else
                # Wrap in pipeline context if there are before/after steps
                rebuild_pipeline(before, find_step, after_)
              end

            before != nil ->
              # 1-arg filter in pipeline context: ... |> Stream.filter(pred)
              rebuild_pipeline(before, find_step, after_)

            true ->
              nil
          end

        if pipeline, do: {pipeline, Sourceror.get_range(node)}
      end
    end)
  end

  # Extract {coll, pred} from a filter call.
  # 2-arg form: {coll, pred}
  # 1-arg form (pipeline): {nil, pred}
  defp extract_filter_parts({{:., _, [_, :filter]}, _, [pred]}), do: {nil, pred}
  defp extract_filter_parts({{:., _, [_, :filter]}, _, [coll, pred]}), do: {coll, pred}

  defp make_find_call(coll, pred) do
    args = if coll, do: [coll, pred], else: [pred]
    {{:., [], [{:__aliases__, [], [:Enum]}, :find]}, [], args}
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

  defp check_node({:|>, _, _} = node) do
    steps = flatten_pipeline(node)

    steps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn
      [first, second] ->
        if filter_step?(first) and at_zero_step?(second) do
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

  defp check_node(
         {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta,
          [{{:., _, [mod, :filter]}, _, [_coll, _pred]} = filter_call,
           {:__block__, _, [0]}]}
       ) do
    if filter_module?(mod) do
      {:ok, build_issue_from_nested(meta, filter_call)}
    else
      :error
    end
  end

  defp check_node(_), do: :error

  defp filter_step?({{:., _, [mod, :filter]}, _, args})
       when is_list(args) and length(args) in [1, 2],
       do: filter_module?(mod)

  defp filter_step?(_), do: false

  defp at_zero_step?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [{:__block__, _, [0]}]}
       ),
       do: true

  defp at_zero_step?(_), do: false

  defp filter_module?({:__aliases__, _, [:Stream]}), do: true
  defp filter_module?(_), do: false

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

  defp build_issue(filter_node) do
    {{:., meta, [mod, :filter]}, _, _} = filter_node
    {:__aliases__, _, [mod_name]} = mod

    %Issue{
      rule: :no_filter_then_first,
      message:
        "`#{mod_name}.filter/2` piped into `Enum.at(0)` can be replaced " <>
          "with `Enum.find/2` for a single-pass lazy search.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_issue_from_nested(meta, filter_call) do
    {{:., _, [mod, :filter]}, _, _} = filter_call
    {:__aliases__, _, [mod_name]} = mod

    %Issue{
      rule: :no_filter_then_first,
      message:
        "`#{mod_name}.filter/2` passed to `Enum.at(0)` can be replaced " <>
          "with `Enum.find/2` for a single-pass lazy search.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
