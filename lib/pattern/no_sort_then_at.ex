defmodule Credence.Pattern.NoSortThenAt do
  @moduledoc """
  Performance rule (fixable): Detects `Enum.sort |> Enum.at(index)` where the
  index is a **literal** `0` or `-1` and the sort direction can be statically
  determined. These can be safely replaced with `Enum.min/1` or `Enum.max/1`,
  avoiding the O(n log n) sort entirely.

  ## Recognised direction forms

      Enum.sort(nums)                        # default :asc
      Enum.sort(nums, :asc)                  # explicit atom
      Enum.sort(nums, :desc)                 # explicit atom
      Enum.sort(nums, &>=/2)                 # capture → :desc
      Enum.sort(nums, &<=/2)                 # capture → :asc
      Enum.sort(nums, fn a, b -> a > b end)  # anonymous comparator → :desc
      Enum.sort(nums, fn a, b -> b > a end)  # flipped comparator  → :asc

  ## Not flagged

  Other literal indices like `Enum.sort(nums) |> Enum.at(3)` are not flagged
  because there is no standard-library O(n) replacement for kth-element access.

  Variable indices such as `Enum.sort(nums) |> Enum.at(k - 1)` are not flagged
  because they represent valid kth-element access that genuinely needs a sort.

  Unresolvable directions such as `Enum.sort(nums, dir) |> Enum.at(0)` or
  opaque comparators like `Enum.sort(nums, &MyModule.compare/2) |> Enum.at(0)`
  are not flagged because we cannot determine whether the result is min or max.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline: ... |> Enum.sort(...) |> Enum.at(literal_index)
        {:|>, meta, [left, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, at_args}]} = node,
        issues ->
          sort_args = extract_sort_args(rightmost(left))

          if sort_args && has_endpoint_index?(at_args) &&
               sort_direction(sort_args) != :unknown do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Nested: Enum.at(Enum.sort(...), literal_index)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, sort_args} | rest
         ]} = node,
        issues ->
          if has_endpoint_index?(rest) && sort_direction(sort_args) != :unknown do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Pipeline form: Enum.sort(c, dir?) |> Enum.at(index)
      {:|>, _, [lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, [index_arg]}]} = node ->
        fix_pipe_sort_at(lhs, index_arg, node)

      # Nested form: Enum.at(Enum.sort(c, dir?), index)
      {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, sort_args} | rest
       ]} = node
      when is_list(sort_args) ->
        index_arg = if rest == [], do: nil, else: hd(rest)
        fix_nested_sort_at(sort_args, index_arg, node)

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # ── Pipeline fix ──────────────────────────────────────────────────────────

  defp fix_pipe_sort_at(
         {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, sort_args} = _lhs,
         index_arg,
         node
       )
       when is_list(sort_args) do
    case {literal_index(index_arg), sort_direction(sort_args)} do
      {{:ok, 0}, dir} when dir in [:asc, :desc] -> replacement_call(dir, :first, hd(sort_args))
      {{:ok, -1}, dir} when dir in [:asc, :desc] -> replacement_call(dir, :last, hd(sort_args))
      {_, _} -> node
    end
  end

  defp fix_pipe_sort_at(
         {:|>, pipe_meta, [deeper, {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, sort_args}]},
         index_arg,
         node
       )
       when is_list(sort_args) do
    collection =
      {:|>, pipe_meta, [deeper, {{:., [], [{:__aliases__, [], [:Enum]}, :sort]}, [], []}]}

    case {literal_index(index_arg), sort_direction(sort_args)} do
      {{:ok, 0}, dir} when dir in [:asc, :desc] -> replacement_call(dir, :first, collection)
      {{:ok, -1}, dir} when dir in [:asc, :desc] -> replacement_call(dir, :last, collection)
      {_, _} -> node
    end
  end

  defp fix_pipe_sort_at(_lhs, _index, node), do: node

  # ── Nested fix ────────────────────────────────────────────────────────────

  defp fix_nested_sort_at(sort_args, index_arg, node) do
    case {literal_index(index_arg), sort_direction(sort_args)} do
      {{:ok, 0}, dir} when dir in [:asc, :desc] -> replacement_call(dir, :first, hd(sort_args))
      {{:ok, -1}, dir} when dir in [:asc, :desc] -> replacement_call(dir, :last, hd(sort_args))
      {_, _} -> node
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  # Check if the args to Enum.at contain literal 0 or -1 — the only
  # indices replaceable with Enum.min/max.  Other literal indices (2, 3, …)
  # and variable indices (k - 1, mid) are left alone.
  defp has_endpoint_index?(at_args) do
    case at_args do
      [arg] -> literal_index(arg) in [{:ok, 0}, {:ok, -1}]
      _ -> false
    end
  end

  # Normalise Sourceror's various integer representations into {:ok, n} | :error
  defp literal_index(n) when is_integer(n), do: {:ok, n}
  defp literal_index({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp literal_index({:-, _, [n]}) when is_integer(n), do: {:ok, -n}
  defp literal_index({:-, _, [{:__block__, _, [n]}]}) when is_integer(n), do: {:ok, -n}
  defp literal_index(_), do: :error

  defp sort_direction([_collection]), do: :asc
  defp sort_direction([_collection, {:__block__, _, [dir]}]) when dir in [:asc, :desc], do: dir
  defp sort_direction([_collection, dir]) when dir in [:asc, :desc], do: dir

  # Function captures: &>=/2, &>/2 → :desc; &<=/2, &</2 → :asc
  defp sort_direction([_collection, {:&, _, [{:/, _, [{op, _, _}, 2]}]}])
       when op in [:>=, :>],
       do: :desc

  defp sort_direction([_collection, {:&, _, [{:/, _, [{op, _, _}, 2]}]}])
       when op in [:<=, :<],
       do: :asc

  # Same but with Sourceror wrapping the arity in __block__
  defp sort_direction([_collection, {:&, _, [{:/, _, [{op, _, _}, {:__block__, _, [2]}]}]}])
       when op in [:>=, :>],
       do: :desc

  defp sort_direction([_collection, {:&, _, [{:/, _, [{op, _, _}, {:__block__, _, [2]}]}]}])
       when op in [:<=, :<],
       do: :asc

  # Anonymous comparators: fn a, b -> a OP b end
  # Direct order: params match left/right of comparison
  # Flipped order: params match right/left of comparison
  defp sort_direction([_collection, {:fn, _, [{:->, _, [[p1, p2], {op, _, [left, right]}]}]}])
       when op in [:>, :>=] do
    cond do
      same_var?(p1, left) and same_var?(p2, right) -> :desc
      same_var?(p2, left) and same_var?(p1, right) -> :asc
      true -> :unknown
    end
  end

  defp sort_direction([_collection, {:fn, _, [{:->, _, [[p1, p2], {op, _, [left, right]}]}]}])
       when op in [:<, :<=] do
    cond do
      same_var?(p1, left) and same_var?(p2, right) -> :asc
      same_var?(p2, left) and same_var?(p1, right) -> :desc
      true -> :unknown
    end
  end

  defp sort_direction(_), do: :unknown

  defp same_var?({name, _, _}, {name, _, _}) when is_atom(name), do: true
  defp same_var?(_, _), do: false

  defp extract_sort_args({{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, sort_args})
       when is_list(sort_args),
       do: sort_args

  defp extract_sort_args(_), do: nil

  defp replacement_call(:asc, :first, c), do: make_remote(:Enum, :min, [c])
  defp replacement_call(:asc, :last, c), do: make_remote(:Enum, :max, [c])
  defp replacement_call(:desc, :first, c), do: make_remote(:Enum, :max, [c])
  defp replacement_call(:desc, :last, c), do: make_remote(:Enum, :min, [c])

  defp make_remote(mod, fun, args) do
    {{:., [], [{:__aliases__, [], [mod]}, fun]}, [], args}
  end

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp build_issue(meta) do
    %Issue{
      rule: :no_sort_then_at,
      message:
        "Sorting a list then accessing by literal index is O(n log n) " <>
          "when O(n) suffices. Use `Enum.min/1` or `Enum.max/1` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
