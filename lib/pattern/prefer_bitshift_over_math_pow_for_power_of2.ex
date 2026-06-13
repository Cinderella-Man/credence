defmodule Credence.Pattern.PreferBitshiftOverMathPowForPowerOf2 do
  @moduledoc """
  Detects `trunc(:math.pow(2, x))` and rewrites to `1 <<< trunc(x)`.

  Using `:math.pow/2` with base 2 and then truncating is a floating-point
  roundabout for computing powers of 2. The bitwise left-shift form
  `1 <<< trunc(x)` is identical for all real x, avoids float precision
  risks, and is idiomatic Elixir for power-of-2 arithmetic.

  ## Bad

      trunc(:math.pow(2, highest_bit_index))

  ## Good

      1 <<< trunc(highest_bit_index)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:trunc, meta, [_]} = node, acc ->
          case extract_math_pow_2(node) do
            {:ok, _} ->
              issue = %Issue{
                rule: :prefer_bitshift_over_math_pow_for_power_of2,
                message:
                  "Prefer `1 <<< trunc(x)` over `trunc(:math.pow(2, x))` for power-of-2 arithmetic.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | acc]}

            :error ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, fn
      {:trunc, _meta, [_]} = node ->
        case extract_math_pow_2(node) do
          {:ok, second_arg} ->
            {:<<<, [],
             [
               {:__block__, [], [1]},
               {:trunc, [], [second_arg]}
             ]}

          :error ->
            node
        end

      node ->
        node
    end)
  end

  # Extract the second argument from `trunc(:math.pow(2, arg))`.
  defp extract_math_pow_2({:trunc, _, [call_node]}) do
    case call_node do
      {{:., _, [{:__block__, _, [:math]}, :pow]}, _, [{:__block__, _, [2]}, arg]} ->
        {:ok, arg}

      _ ->
        :error
    end
  end

  defp extract_math_pow_2(_), do: :error
end
