defmodule Credence.Pattern.NoCombinedMinMaxReduce do
  @moduledoc """
  Flags `Enum.reduce/3` that computes both min AND max in a single pass
  with a 2-tuple accumulator. Prefer `Enum.min_max/1` instead.

  Detects both `<`/`>` comparison patterns and `min()`/`max()` kernel
  call patterns inside the reduce body.

  ## Bad

      Enum.reduce(list, {nil, nil}, fn elem, {min_acc, max_acc} ->
        min_val = if min_acc == nil or elem < min_acc, do: elem, else: min_acc
        max_val = if max_acc == nil or elem > max_acc, do: elem, else: max_acc
        {min_val, max_val}
      end)

      Enum.reduce(list, {hd(list), hd(list)}, fn elem, {max_acc, min_acc} ->
        new_max = max(elem, max_acc)
        new_min = min(elem, min_acc)
        {new_max, new_min}
      end)

  ## Good

      Enum.min_max(list)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and combined_min_max?(args) do
            issue = %Issue{
              rule: :no_combined_min_max_reduce,
              message:
                "Combined min/max reduction detected. Prefer Enum.min_max/1.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # --- private ---

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  # Piped: Enum.reduce(acc, fun) — 2 args
  defp combined_min_max?([_acc, fun]), do: match_fun?(fun)
  # Direct: Enum.reduce(enum, acc, fun) — 3 args
  defp combined_min_max?([_enum, _acc, fun]), do: match_fun?(fun)
  defp combined_min_max?(_), do: false

  defp match_fun?({:fn, _, [{:->, _, [params, body]}]}) do
    case params do
      [_elem_param, acc_param] ->
        two_tuple_param?(acc_param) and min_max_body?(body)

      _ ->
        false
    end
  end

  defp match_fun?(_), do: false

  # The accumulator param must be a 2-tuple pattern: {min, max}
  defp two_tuple_param?({min, max}) do
    simple_var?(min) and simple_var?(max)
  end

  defp two_tuple_param?({:__block__, _, [inner]}), do: two_tuple_param?(inner)
  defp two_tuple_param?(_), do: false

  # Body must contain both min and max operations — either via `<`/`>` comparisons
  # or `Kernel.min/2`/`Kernel.max/2` calls — and return a 2-tuple of simple variables.
  defp min_max_body?({:__block__, _, [_ | _] = exprs}) do
    {has_lt, has_gt, has_max_call, has_min_call} =
      Enum.reduce(exprs, {false, false, false, false}, fn expr, {lt, gt, mx, mn} ->
        {lt or contains_lt?(expr), gt or contains_gt?(expr),
         mx or contains_max_call?(expr), mn or contains_min_call?(expr)}
      end)

    ((has_lt and has_gt) or (has_max_call and has_min_call)) and
      returns_2_tuple?(List.last(exprs))
  end

  defp min_max_body?(_), do: false

  # Check for `<` comparison anywhere in the expression tree
  defp contains_lt?({:<, _, [_, _]}), do: true
  defp contains_lt?(node) do
    {_found, result} =
      Macro.prewalk(node, false, fn
        {:<, _, [_, _]} = child, _acc -> {child, true}
        child, acc -> {child, acc}
      end)
    result
  end

  # Check for `>` comparison anywhere in the expression tree
  defp contains_gt?({:>, _, [_, _]}), do: true
  defp contains_gt?(node) do
    {_found, result} =
      Macro.prewalk(node, false, fn
        {:>, _, [_, _]} = child, _acc -> {child, true}
        child, acc -> {child, acc}
      end)
    result
  end

  # Check for `Kernel.max/2` call anywhere in the expression tree
  defp contains_max_call?({:max, _, [_, _]}), do: true
  defp contains_max_call?(node) do
    {_found, result} =
      Macro.prewalk(node, false, fn
        {:max, _, [_, _]} = child, _acc -> {child, true}
        child, acc -> {child, acc}
      end)
    result
  end

  # Check for `Kernel.min/2` call anywhere in the expression tree
  defp contains_min_call?({:min, _, [_, _]}), do: true
  defp contains_min_call?(node) do
    {_found, result} =
      Macro.prewalk(node, false, fn
        {:min, _, [_, _]} = child, _acc -> {child, true}
        child, acc -> {child, acc}
      end)
    result
  end

  # Check that the expression returns a 2-tuple of simple variables
  defp returns_2_tuple?({a, b}), do: simple_var?(a) and simple_var?(b)
  defp returns_2_tuple?({:__block__, _, [inner]}), do: returns_2_tuple?(inner)
  defp returns_2_tuple?(_), do: false

  defp simple_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp simple_var?(_), do: false
end
