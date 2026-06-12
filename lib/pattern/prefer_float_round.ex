defmodule Credence.Pattern.PreferFloatRound do
  @moduledoc """
  Replaces `:erlang.round(x * 100) / 100` with `Float.round(x, 2)`.

  LLMs (and developers) use the manual rounding trick
  `:erlang.round(x * 100) / 100` to round a float to two decimal places.
  The standard-library equivalent `Float.round(x, 2)` is clearer, shorter,
  and communicates intent directly.

  Only fires when the pattern is `:erlang.round(expr * 100) / 100` — the
  multiplier and divisor must both be the integer literal `100`, and the
  outer operation must be division by that same `100`.

  ## Behaviour note

  `Float.round/2` only accepts floats (it raises `FunctionClauseError` on
  integers). The manual trick `:erlang.round(x * 100) / 100` works on
  integers too (because `/` always returns a float). This rule is therefore
  only safe when `x` is known to be a float — which is the overwhelmingly
  common case for a rounding site (the input is already the result of a
  division, a float literal, or an arithmetic expression producing a float).

  ## Bad

      average = (grade1 + grade2 + grade3) / 3
      :erlang.round(average * 100) / 100

  ## Good

      average = (grade1 + grade2 + grade3) / 3
      Float.round(average, 2)
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
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      node -> maybe_rewrite(node)
    end)
  end

  # Match: :erlang.round(expr * 100) / 100
  defp check_node({:/, meta, [round_call, divisor]}) do
    with {:ok, _inner_expr} <- extract_erlang_round_times100(round_call),
         true <- literal_100?(divisor) do
      {:ok,
       %Issue{
         rule: :prefer_float_round,
         message:
           "Use `Float.round(x, 2)` instead of `:erlang.round(x * 100) / 100` " <>
             "for rounding a float to two decimal places.",
         meta: %{line: Keyword.get(meta, :line)}
       }}
    else
      _ -> :error
    end
  end

  defp check_node(_), do: :error

  # Rewrite: :erlang.round(expr * 100) / 100 → Float.round(expr, 2)
  defp maybe_rewrite({:/, _meta, [round_call, divisor]} = node) do
    with {:ok, inner_expr} <- extract_erlang_round_times100(round_call),
         true <- literal_100?(divisor) do
      float_round(inner_expr)
    else
      _ -> node
    end
  end

  defp maybe_rewrite(node), do: node

  # Extract the inner expression from :erlang.round(expr * 100),
  # returning {:ok, expr} or :error.
  defp extract_erlang_round_times100(
         {{:., _, [{:__block__, _, [:erlang]}, :round]}, _, [mult_expr]}
       ) do
    case mult_expr do
      {:*, _, [inner, {:__block__, _, [100]}]} -> {:ok, inner}
      {:*, _, [{:__block__, _, [100]}, inner]} -> {:ok, inner}
      _ -> :error
    end
  end

  defp extract_erlang_round_times100(_), do: :error

  # Check if a node is the integer literal 100.
  defp literal_100?({:__block__, _, [100]}), do: true
  defp literal_100?(_), do: false

  # Build: Float.round(expr, 2)
  defp float_round(expr) do
    {{:., [], [{:__aliases__, [], [:Float]}, :round]}, [], [expr, {:__block__, [], [2]}]}
  end
end
