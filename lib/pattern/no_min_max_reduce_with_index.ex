defmodule Credence.Pattern.NoMinMaxReduceWithIndex do
  @moduledoc """
  Flags `Enum.reduce/3` that tracks min/max with an index (or other metadata)
  in a 2-tuple accumulator.  Prefer `Enum.min_by/2` or `Enum.max_by/2` instead.

  ## Bad

      list
      |> Enum.with_index()
      |> Enum.reduce({first, 0}, fn {elem, idx}, {min_val, min_idx} ->
        if elem < min_val, do: {elem, idx}, else: {min_val, min_idx}
      end)
      |> elem(1)

  ## Good

      list
      |> Enum.with_index()
      |> Enum.min_by(fn {x, _} -> x end)
      |> elem(1)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and min_max_tuple_body?(args) do
            issue = %Issue{
              rule: :no_min_max_reduce_with_index,
              message:
                "Reduce used to track min/max with index — " <>
                  "prefer Enum.min_by/2 or Enum.max_by/2.",
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
  defp min_max_tuple_body?([_acc, fun]), do: match_fun?(fun)
  # Direct: Enum.reduce(enum, acc, fun) — 3 args
  defp min_max_tuple_body?([_enum, _acc, fun]), do: match_fun?(fun)
  defp min_max_tuple_body?(_), do: false

  defp match_fun?({:fn, _, [{:->, _, [params, body]}]}) do
    with {:ok, e_vars, a_vars} <- tuple_params(params) do
      min_max_if?(body, e_vars, a_vars)
    else
      _ -> false
    end
  end

  defp match_fun?(_), do: false

  # Two tuple-pattern params, each holding two variable references.
  # Sourceror wraps 2-tuples in {:__block__, meta, [tuple]}.
  defp tuple_params([p1, p2]) do
    with {a, b} <- unwrap_block(p1),
         {c, d} <- unwrap_block(p2),
         true <- var?(a) and var?(b) and var?(c) and var?(d) do
      {:ok, [name(a), name(b)], [name(c), name(d)]}
    else
      _ -> :error
    end
  end

  defp tuple_params(_), do: :error

  defp unwrap_block({:__block__, _, [inner]}), do: inner
  defp unwrap_block(other), do: other

  # Body must be an if/comparison with tuple-only branches
  defp min_max_if?({:__block__, _, [_ | _] = exprs}, e_vars, a_vars),
    do: min_max_if?(List.last(exprs), e_vars, a_vars)

  defp min_max_if?({:if, _, [comparison, opts]}, e_vars, a_vars) do
    cross_tuple_comparison?(comparison, e_vars, a_vars) and tuple_branches?(opts)
  end

  defp min_max_if?(_, _, _), do: false

  # Comparison must involve one variable from each param tuple
  defp cross_tuple_comparison?({op, _, [a, b]}, e_vars, a_vars)
       when op in [:<, :<=, :>, :>=] do
    a_name = name(a)
    b_name = name(b)

    (a_name in e_vars and b_name in a_vars) or
      (a_name in a_vars and b_name in e_vars)
  end

  defp cross_tuple_comparison?(_, _, _), do: false

  # Both branches must return 2-tuples of bare variable references
  defp tuple_branches?(opts) do
    with {:ok, do_expr} <- kw_value(opts, :do),
         {:ok, else_expr} <- kw_value(opts, :else) do
      var_tuple?(do_expr) and var_tuple?(else_expr)
    else
      _ -> false
    end
  end

  defp var_tuple?(node) do
    case unwrap_block(node) do
      {a, b} -> var?(a) and var?(b)
      _ -> false
    end
  end

  defp var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp var?(_), do: false

  defp name({n, _, _}), do: n

  # Sourceror wraps keyword keys as {{:__block__, _, [:key]}, value}
  defp kw_value(opts, key) do
    case Keyword.get(opts, key) do
      nil ->
        Enum.find_value(opts, :error, fn
          {{:__block__, _, [^key]}, value} -> {:ok, value}
          _ -> nil
        end)

      value ->
        {:ok, value}
    end
  end
end
