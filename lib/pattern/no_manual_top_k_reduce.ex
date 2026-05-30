defmodule Credence.Pattern.NoManualTopKReduce do
  @moduledoc """
  Flags manual tracking of K extreme values via `Enum.reduce/3` with a tuple
  accumulator and `cond`-based comparison logic.

  When the goal is to find the K smallest (or largest) elements, the idiomatic
  Elixir approach is `Enum.sort/1 |> Enum.take(k)`, not a manual reduce with
  a tuple accumulator and comparison branches.

  ## Flagged patterns

      # Tracking two smallest values via reduce
      Enum.reduce(rest, {min1, min2}, fn elem, {a, b} ->
        cond do
          elem < a -> {elem, a}
          elem < b -> {a, elem}
          true -> {a, b}
        end
      end)

  ## Suggested replacement

      list |> Enum.sort() |> Enum.take(2) |> Enum.sum()

  This is a **check-only** rule — no automatic fix is provided because the
  appropriate aggregation (sum, min, max, etc.) cannot be inferred from the
  reduce expression alone.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, issues ->
          case match_top_k_reduce(node) do
            {:ok, line} ->
              issue = %Issue{
                rule: :no_manual_top_k_reduce,
                message:
                  "Manual tracking of K extreme values via reduce with tuple accumulator. " <>
                    "Prefer Enum.sort/1 |> Enum.take(k) for clarity.",
                meta: %{line: line}
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

  # Top-level match: Enum.reduce call with tuple accumulator and cond body
  defp match_top_k_reduce({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, args}) do
    if manual_top_k_body?(args), do: {:ok, Keyword.get(meta, :line)}, else: :error
  end

  defp match_top_k_reduce({{:., _, [:Enum, :reduce]}, meta, args}) do
    if manual_top_k_body?(args), do: {:ok, Keyword.get(meta, :line)}, else: :error
  end

  defp match_top_k_reduce(_), do: :error

  # Matches: Enum.reduce(enum, {a, b}, fn elem, {c, d} -> cond do ... end end)
  # The tuple accumulator may be bare {a, b} or Sourceror-wrapped {:__block__, _, [{a, b}]}
  defp manual_top_k_body?([_enum, acc, {:fn, _, [{:->, _, [_params, body]}]}]) do
    tuple_acc?(acc) and cond_with_comparisons?(body)
  end

  defp manual_top_k_body?(_), do: false

  defp tuple_acc?({_, _}), do: true
  defp tuple_acc?({:__block__, _, [{_, _}]}), do: true
  defp tuple_acc?(_), do: false

  # --- cond analysis ---

  defp cond_with_comparisons?(body) do
    case body do
      {:cond, _, [[{{:__block__, _, [:do]}, clauses}]]} when is_list(clauses) ->
        check_clauses(clauses)

      _ ->
        false
    end
  end

  # Need at least 3 clauses: two comparisons + catch-all true
  defp check_clauses(clauses) when length(clauses) >= 3 do
    Enum.all?(clauses, &valid_clause?/1)
  end

  defp check_clauses(_), do: false

  defp valid_clause?({:->, _, [[condition], body]}) do
    tuple_body?(body) and (comparison_condition?(condition) or catch_all_condition?(condition))
  end

  defp valid_clause?(_), do: false

  # --- condition checks ---

  defp comparison_condition?({:<, _, [_, _]}), do: true
  defp comparison_condition?({:<=, _, [_, _]}), do: true
  defp comparison_condition?({:>, _, [_, _]}), do: true
  defp comparison_condition?({:>=, _, [_, _]}), do: true
  defp comparison_condition?(_), do: false

  defp catch_all_condition?({:__block__, _, [true]}), do: true
  defp catch_all_condition?(:true), do: true
  defp catch_all_condition?(_), do: false

  # --- body checks ---

  defp tuple_body?({_, _}), do: true
  defp tuple_body?({:__block__, _, [{_, _}]}), do: true
  defp tuple_body?(_), do: false
end
