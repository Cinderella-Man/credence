defmodule Credence.Pattern.NoReduceRangeWithElem do
  @moduledoc """
  Check-only rule: Detects `Enum.reduce/3` iterating over a range with
  `elem/2` used on the range variable to access elements by index from
  tuples or lists.

  ## Why this matters

  Using `Enum.reduce` over `0..(n-1)` with `elem/2` to access elements
  by index is a manual zip-and-map pattern. The idiomatic Elixir
  approach uses `Enum.zip/2` and `Enum.map/2` instead.

  LLMs frequently produce this pattern when translating index-based
  loops from other languages.

  ## Flagged patterns

      # Manual zip+map via reduce over range with elem
      Enum.reduce(0..(n - 1), [], fn index, acc ->
        [elem(tuple1, index) + elem(tuple2, index) | acc]
      end)
      |> Enum.reverse()

      # With then/2 and explicit List.to_tuple
      Enum.reduce(0..(min - 1), [], fn i, acc ->
        (elem(tup1, i) + elem(tup2, i)) |> then(&[&1 | acc])
      end)
      |> Enum.reverse()
      |> List.to_tuple()

  ## Good

      Tuple.to_list(tuple1)
      |> Enum.zip(Tuple.to_list(tuple2))
      |> Enum.map(fn {a, b} -> a + b end)
      |> List.to_tuple()

      # Single tuple:
      Tuple.to_list(tuple)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, issues ->
          case detect_pattern(node) do
            {:ok, meta} ->
              issue = %Issue{
                rule: :no_reduce_range_with_elem,
                message:
                  "`Enum.reduce` over a range with `elem/2` to access elements by index is " <>
                    "a manual zip+map pattern. Use `Enum.zip/2` + `Enum.map/2` instead, " <>
                    "or `Tuple.to_list/1` for a single collection.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | issues]}

            :error ->
              {node, issues}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # -- detection ---------------------------------------------------------------

  # Direct: Enum.reduce(0..n, [], fn i, acc -> ... elem(tup, i) ... end)
  defp detect_pattern({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, args}) do
    detect_reduce_args(args, meta)
  end

  # Piped: 0..n |> Enum.reduce([], fn i, acc -> ... end)
  defp detect_pattern({:|>, _, [range, {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_acc, {:fn, _, clauses}]}]}) do
    if range_literal?(range) do
      case clauses do
        [{:->, _, [[{var_name, _, ctx}, _acc_param], body]} | _]
        when is_atom(var_name) and is_atom(ctx) ->
          if body_has_elem_with_var?(body, var_name), do: {:ok, meta}, else: :error

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp detect_pattern(_), do: :error

  defp detect_reduce_args([enum, _acc, {:fn, _, clauses}], meta) do
    if range_literal?(enum) and uses_elem_by_range_var?(clauses) do
      {:ok, meta}
    else
      :error
    end
  end

  defp detect_reduce_args(_, _), do: :error

  # Check if the enum arg is a range literal like 0..n or 0..(n-1)
  defp range_literal?({:.., _, _}), do: true
  defp range_literal?({:__block__, _, [{:.., _, _}]}), do: true
  defp range_literal?(_), do: false

  # Extract the range start variable name from the range literal
  # and check if elem/2 uses it in the fn body
  defp uses_elem_by_range_var?(clauses) do
    # Extract the first element of the range to know what the range variable is
    # In 0..n, the fn's first param receives each integer from the range
    # We need to check if the fn's first param is used in elem/2 calls
    case clauses do
      [{:->, _, [[{var_name, _, ctx} = _index_param, _acc_param], body]} | _]
      when is_atom(var_name) and is_atom(ctx) ->
        body_has_elem_with_var?(body, var_name)

      _ ->
        false
    end
  end

  # Check if the body contains elem(some_expr, var_name) where var_name matches
  defp body_has_elem_with_var?(body, var_name) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        # Local call: elem(collection, index_var) — most common in Elixir
        {:elem, _, [_collection, {name, _, ctx}]} = node, _acc
        when is_atom(name) and is_atom(ctx) and name == var_name ->
          {node, true}

        # Qualified: Kernel.elem(collection, index_var)
        {{:., _, [{:__aliases__, _, [:Kernel]}, :elem]}, _, [_collection, {name, _, ctx}]} = node,
        _acc
        when is_atom(name) and is_atom(ctx) and name == var_name ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end
end
