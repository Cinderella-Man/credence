defmodule Credence.Pattern.NoEnumTakeNegative do
  @moduledoc """
  Performance rule: Detects `Enum.take(list, -n)` where `n` is a positive
  integer literal.

  For linked lists, `Enum.take(list, -n)` must internally determine the list
  length, then traverse again to the cut point — effectively two full
  traversals.

  The auto-fix replaces `Enum.take(list, -n)` with `Enum.slice(list, -n..-1//1)`.
  When `Enum.take(-n)` directly follows `Enum.sort()` in a pipeline, the fix
  defers to `PreferDescSortOverNegativeTake`.

  ## Bad

      defmodule BadOneNETN do
        def last(list), do: Enum.take(list, -1)
      end

  ## Good

      defmodule BadOneNETN do
        def last(list), do: Enum.slice(list, -1..-1//1)
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, meta, [_list, idx_node]} = node, issues ->
          case extract_negative(idx_node) do
            {:ok, n} -> {node, [build_issue(n, meta) | issues]}
            :error -> {node, issues}
          end

        {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, meta, [idx_node]} = node, issues ->
          case extract_negative(idx_node) do
            {:ok, n} -> {node, [build_issue(n, meta) | issues]}
            :error -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    skip = sort_take_lines(ast)

    RuleHelpers.patches_from_postwalk(ast, fn
      {{:., meta, [{:__aliases__, _, [:Enum]}, :take]}, _, [list_arg, second]} = node ->
        if Keyword.get(meta, :line) in skip do
          node
        else
          case extract_negative(second) do
            {:ok, n} -> enum_slice_call(list_arg, n)
            :error -> node
          end
        end

      {{:., meta, [{:__aliases__, _, [:Enum]}, :take]}, _, [single]} = node ->
        if Keyword.get(meta, :line) in skip do
          node
        else
          case extract_negative(single) do
            {:ok, n} -> enum_slice_piped(n)
            :error -> node
          end
        end

      node ->
        node
    end)
  end

  defp sort_take_lines(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:|>, _, [lhs, {{:., meta, [{:__aliases__, _, [:Enum]}, :take]}, _, args}]} = node, acc ->
          if pipe_ends_with_plain_sort?(lhs) and negative_take_args?(args) do
            {node, MapSet.put(acc, Keyword.get(meta, :line))}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    lines
  end

  defp negative_take_args?([{:-, _, [{:__block__, _, [n]}]}]) when is_integer(n) and n > 0,
    do: true

  defp negative_take_args?([_, {:-, _, [{:__block__, _, [n]}]}]) when is_integer(n) and n > 0,
    do: true

  defp negative_take_args?(_), do: false

  # "Plain sort" = Enum.sort() with 0 args OR Enum.sort(list) with 1 non-direction arg
  defp pipe_ends_with_plain_sort?({{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args}),
    do: plain_sort_args?(args)

  defp pipe_ends_with_plain_sort?({:|>, _, [_lhs, rhs]}),
    do: pipe_ends_with_plain_sort?(rhs)

  defp pipe_ends_with_plain_sort?(_), do: false

  defp plain_sort_args?([]), do: true
  defp plain_sort_args?([arg]), do: not sort_direction_or_comparator?(arg)
  defp plain_sort_args?(_), do: false

  defp sort_direction_or_comparator?(:asc), do: true
  defp sort_direction_or_comparator?(:desc), do: true
  defp sort_direction_or_comparator?({:__block__, _, [:asc]}), do: true
  defp sort_direction_or_comparator?({:__block__, _, [:desc]}), do: true
  defp sort_direction_or_comparator?({:fn, _, _}), do: true
  defp sort_direction_or_comparator?({:&, _, _}), do: true
  defp sort_direction_or_comparator?(_), do: false

  defp extract_negative({:-, _, [{:__block__, _, [n]}]}) when is_integer(n) and n > 0,
    do: {:ok, n}

  defp extract_negative(_), do: :error

  defp enum_slice_call(list_arg, n),
    do: {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [list_arg, build_range(n)]}

  defp enum_slice_piped(n),
    do: {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [build_range(n)]}

  defp build_range(n), do: {:..//, [], [-n, -1, 1]}

  defp build_issue(n, meta) do
    %Issue{
      rule: :no_enum_take_negative,
      message:
        "`Enum.take(list, -#{n})` forces a double traversal of the list to take from the end. " <>
          "Sort in the opposite direction and use `Enum.take(list, #{n})` instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
