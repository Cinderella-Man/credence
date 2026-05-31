defmodule Credence.Pattern.NoRangeComparisonForMembership do
  @moduledoc """
  Detects `x >= a and x <= b` (or reversed operands) that should be `x in a..b`.

  LLMs frequently express numeric range checks as two separate comparisons
  joined by `and`, instead of using Elixir's `in` operator with a range.
  When both bounds are integer literals and `a <= b`, the `in` form is
  more idiomatic and equally readable.

  ## Bad

      x >= 10 and x <= 25
      x >= 10 and 25 >= x
      10 <= x and x <= 25

  ## Good

      x in 10..25

  ## Auto-fix

  Rewrites the comparison pair to `x in a..b`. The fix handles all four
  operand orderings. Both bounds must be integer literals with `a <= b`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, acc ->
          case detect_range_comparison(node) do
            {:ok, _var, _low_node, _high_node} ->
              meta = elem(node, 1) || []
              {node, [build_issue(meta) | acc]}

            :skip ->
              {node, acc}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case detect_range_comparison(node) do
        {:ok, var, low_node, high_node} ->
          meta = elem(node, 1) || []
          {:in, meta, [var, {:.., meta, [low_node, high_node]}]}

        :skip ->
          node
      end
    end)
  end

  # Pattern 1: var >= low and var <= high
  defp detect_range_comparison(
         {:and, _,
          [
            {:>=, _, [var_a, low_block]},
            {:<=, _, [var_b, high_block]}
          ]}
       ) do
    with {:ok, low} <- unwrap_integer(low_block),
         {:ok, high} <- unwrap_integer(high_block),
         true <- low <= high and same_var?(var_a, var_b) do
      {:ok, var_a, low_block, high_block}
    else
      _ -> :skip
    end
  end

  # Pattern 2: var >= low and high >= var
  defp detect_range_comparison(
         {:and, _,
          [
            {:>=, _, [var_a, low_block]},
            {:>=, _, [high_block, var_b]}
          ]}
       ) do
    with {:ok, low} <- unwrap_integer(low_block),
         {:ok, high} <- unwrap_integer(high_block),
         true <- low <= high and same_var?(var_a, var_b) do
      {:ok, var_a, low_block, high_block}
    else
      _ -> :skip
    end
  end

  # Pattern 3: low <= var and var <= high
  defp detect_range_comparison(
         {:and, _,
          [
            {:<=, _, [low_block, var_a]},
            {:<=, _, [var_b, high_block]}
          ]}
       ) do
    with {:ok, low} <- unwrap_integer(low_block),
         {:ok, high} <- unwrap_integer(high_block),
         true <- low <= high and same_var?(var_a, var_b) do
      {:ok, var_a, low_block, high_block}
    else
      _ -> :skip
    end
  end

  # Pattern 4: low <= var and high >= var
  defp detect_range_comparison(
         {:and, _,
          [
            {:<=, _, [low_block, var_a]},
            {:>=, _, [high_block, var_b]}
          ]}
       ) do
    with {:ok, low} <- unwrap_integer(low_block),
         {:ok, high} <- unwrap_integer(high_block),
         true <- low <= high and same_var?(var_a, var_b) do
      {:ok, var_a, low_block, high_block}
    else
      _ -> :skip
    end
  end

  defp detect_range_comparison(_), do: :skip

  # Sourceror wraps literals in {:__block__, meta, [value]}.
  defp unwrap_integer({:__block__, _, [n]}) when is_integer(n), do: {:ok, n}
  defp unwrap_integer(n) when is_integer(n), do: {:ok, n}
  defp unwrap_integer(_), do: :error

  # Check if two AST nodes represent the same variable.
  defp same_var?({name, _, ctx}, {name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp same_var?(_, _), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_range_comparison_for_membership,
      message:
        "Use `x in a..b` instead of `x >= a and x <= b` for integer range membership.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
