defmodule Credence.Pattern.PreferDescSortOverNegativeTake do
  @moduledoc """
  Prefer `Enum.sort(nums, :desc) |> Enum.take(n) |> Enum.reverse()`
  over `Enum.sort(nums) |> Enum.take(-n)`.

  `Enum.take(list, -n)` must walk the whole list to reach the last `n`;
  `Enum.take(list, n)` stops after `n`. The trailing `Enum.reverse/1` is
  **load-bearing for correctness**: `sort |> take(-n)` returns the n largest in
  *ascending* order, while `sort(:desc) |> take(n)` returns them *descending*,
  so the reverse restores the original order. The rewrite is behaviour-preserving
  and reverses only `n` elements.

  ## Bad

      nums
      |> Enum.sort()
      |> Enum.take(-3)

      Enum.sort(nums) |> Enum.take(-3)

  ## Good

      nums
      |> Enum.sort(:desc)
      |> Enum.take(3)
      |> Enum.reverse()

      Enum.sort(nums, :desc) |> Enum.take(3) |> Enum.reverse()
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, meta, _} = node, acc ->
          pipeline = flatten_pipeline(node)

          if match_pattern?(pipeline) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:|>, _, _} = node ->
        pipeline = flatten_pipeline(node)

        if match_pattern?(pipeline) and adjacent_sort_take?(pipeline) do
          transform_pipeline(node)
        else
          node
        end

      node ->
        node
    end)
  end

  # Rebuild the flattened pipeline: rewrite `sort`→`sort(:desc)` and
  # `take(-n)`→`take(n)`, and insert `Enum.reverse()` immediately after the
  # rewritten take. `sort |> take(-n)` yields the n largest in ASCENDING order;
  # `sort(:desc) |> take(n)` yields them DESCENDING, so the trailing reverse
  # restores the original order — making the rewrite behaviour-preserving
  # (and still cheaper: take(n) from the front + reversing n elements beats
  # take(-n) traversing the whole list).
  defp transform_pipeline(node) do
    node
    |> flatten_pipeline()
    |> Enum.flat_map(fn step ->
      if negative_take?(step),
        do: [transform_step(step), enum_reverse_step()],
        else: [transform_step(step)]
    end)
    |> pipe_from_steps()
  end

  defp pipe_from_steps([first | rest]),
    do: Enum.reduce(rest, first, fn step, acc -> {:|>, [], [acc, step]} end)

  defp enum_reverse_step,
    do: {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], []}

  # Enum.sort() → Enum.sort(:desc)  (piped, 0 args)
  defp transform_step({{:., dm, [{:__aliases__, am, [:Enum]}, :sort]}, cm, []}) do
    {{:., dm, [{:__aliases__, am, [:Enum]}, :sort]}, cm, [wrap_literal(:desc)]}
  end

  # Enum.sort(list) → Enum.sort(list, :desc)  (direct call, 1 arg that isn't a direction)
  defp transform_step({{:., dm, [{:__aliases__, am, [:Enum]}, :sort]}, cm, [arg]} = node) do
    if sort_direction_or_comparator?(arg) do
      node
    else
      {{:., dm, [{:__aliases__, am, [:Enum]}, :sort]}, cm, [arg, wrap_literal(:desc)]}
    end
  end

  # Enum.take(-n) → Enum.take(n)
  defp transform_step({{:., dm, [{:__aliases__, am, [:Enum]}, :take]}, cm, [n]}) do
    case positive_value(n) do
      {:ok, pos} ->
        {{:., dm, [{:__aliases__, am, [:Enum]}, :take]}, cm, [wrap_literal(pos)]}

      :error ->
        {{:., dm, [{:__aliases__, am, [:Enum]}, :take]}, cm, [n]}
    end
  end

  defp transform_step(node), do: node

  defp sort_direction_or_comparator?(:asc), do: true
  defp sort_direction_or_comparator?(:desc), do: true
  defp sort_direction_or_comparator?({:__block__, _, [:asc]}), do: true
  defp sort_direction_or_comparator?({:__block__, _, [:desc]}), do: true
  defp sort_direction_or_comparator?({:fn, _, _}), do: true
  defp sort_direction_or_comparator?({:&, _, _}), do: true
  defp sort_direction_or_comparator?(_), do: false

  # "Plain sort" = default ascending, either piped (0 args) or direct (1 list arg)

  defp plain_sort_args?([]), do: true
  defp plain_sort_args?([arg]), do: not sort_direction_or_comparator?(arg)
  defp plain_sort_args?(_), do: false

  defp plain_sort?({{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args}),
    do: plain_sort_args?(args)

  defp plain_sort?(_), do: false

  defp wrap_literal(atom) when is_atom(atom),
    do: {:__block__, [token: inspect(atom)], [atom]}

  defp wrap_literal(int) when is_integer(int),
    do: {:__block__, [token: Integer.to_string(int)], [int]}

  defp positive_value({:-, _, [{:__block__, _, [int]}]}) when is_integer(int),
    do: {:ok, int}

  defp positive_value({:__block__, _, [int]}) when is_integer(int), do: {:ok, int}
  defp positive_value(_), do: :error

  defp adjacent_sort_take?(pipeline) do
    pipeline
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn
      [s, t] -> plain_sort?(s) and negative_take?(t)
      _ -> false
    end)
  end

  defp negative_take?({{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [n]}),
    do: negative_integer?(n)

  defp negative_take?(_), do: false

  defp flatten_pipeline({:|>, _, [left, right]}),
    do: flatten_pipeline(left) ++ [right]

  defp flatten_pipeline(other), do: [other]

  defp match_pattern?(pipeline),
    do: has_plain_sort?(pipeline) and has_negative_take?(pipeline)

  defp has_plain_sort?(pipeline) do
    Enum.any?(pipeline, fn
      {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args} -> plain_sort_args?(args)
      _ -> false
    end)
  end

  defp has_negative_take?(pipeline) do
    Enum.any?(pipeline, fn
      {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _, [n]} -> negative_integer?(n)
      _ -> false
    end)
  end

  defp negative_integer?({:-, _, [{:__block__, _, [int]}]}) when is_integer(int), do: true
  defp negative_integer?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_desc_sort_over_negative_take,
      message: """
      Prefer `Enum.sort(nums, :desc) |> Enum.take(3) |> Enum.reverse()`
      over `Enum.sort(nums) |> Enum.take(-3)`: take(n) from the front avoids
      walking the whole list, and the reverse keeps the result order identical.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
