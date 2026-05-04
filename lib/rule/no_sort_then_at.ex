defmodule Credence.Rule.NoSortThenAt do
  @moduledoc """
  Performance rule (fixable subset): Detects `Enum.sort |> Enum.at(index)` where
  the index is a **literal** `0` or `-1`. These can be safely replaced with
  `Enum.min/1` or `Enum.max/1`, avoiding the O(n log n) sort entirely.

  ## Bad (fixable)

      Enum.sort(nums, :desc) |> Enum.at(0)
      Enum.at(Enum.sort(nums), 0)
      Enum.sort(nums, :asc) |> Enum.at(-1)

  ## Good

      Enum.max(nums)
      Enum.min(nums)
      Enum.max(nums)

  ## Not auto-fixed (delegated to LLM)

  Variable indices such as `Enum.sort(nums) |> Enum.at(k - 1)` or custom
  comparators are still flagged by `check/2` but require human/LLM judgement
  to rewrite.
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline: ... |> Enum.sort(...) |> Enum.at(...)
        {:|>, meta, [left, right]} = node, issues ->
          if remote_call?(right, :Enum, :at) and remote_call?(rightmost(left), :Enum, :sort) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        # Nested: Enum.at(Enum.sort(...), index)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, _} | _rest
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

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

  # lhs is itself an Enum.sort(...) call (single-step pipeline)
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

  # lhs is a pipeline ending in Enum.sort(...)  (multi-step pipeline)
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

  # Anything else — leave unchanged
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

  # Normalise Sourceror's various integer representations into {:ok, n} | :error
  defp literal_index(n) when is_integer(n), do: {:ok, n}
  defp literal_index({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp literal_index({:-, _, [n]}) when is_integer(n), do: {:ok, -n}
  defp literal_index({:-, _, [{:__block__, _, [n]}]}) when is_integer(n), do: {:ok, -n}
  defp literal_index(_), do: :error

  # Determine sort direction from the arguments to Enum.sort/1 or /2.
  # Returns :asc | :desc | :unknown
  defp sort_direction([_collection]), do: :asc
  defp sort_direction([_collection, {:__block__, _, [dir]}]) when dir in [:asc, :desc], do: dir
  defp sort_direction([_collection, dir]) when dir in [:asc, :desc], do: dir
  defp sort_direction(_), do: :unknown

  # Build Enum.min/1 or Enum.max/1
  defp replacement_call(:asc, :first, c), do: make_remote(:Enum, :min, [c])
  defp replacement_call(:asc, :last, c), do: make_remote(:Enum, :max, [c])
  defp replacement_call(:desc, :first, c), do: make_remote(:Enum, :max, [c])
  defp replacement_call(:desc, :last, c), do: make_remote(:Enum, :min, [c])

  defp make_remote(mod, fun, args) do
    {{:., [], [{:__aliases__, [], [mod]}, fun]}, [], args}
  end

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_sort_then_at,
      message:
        "Sorting a list and then accessing a single element with `Enum.at/2` is O(n log n) " <>
          "when you may only need O(n). For min/max, use `Enum.min/1` or `Enum.max/1`. " <>
          "For top-k, consider `Enum.take/2` on the sorted result.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
