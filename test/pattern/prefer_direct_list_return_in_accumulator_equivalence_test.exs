defmodule Credence.Pattern.PreferDirectListReturnInAccumulatorEquivalenceTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferDirectListReturnInAccumulator

  test "fix preserves behaviour" do
    assert_equivalent_module(
      """
      defmodule EquivBefore do
        def dec_to_bin_stack(0), do: ""

        def dec_to_bin_stack(number) when is_integer(number) and number > 0 do
          {stack, _} = convert_to_stack(number, [])
          Enum.join(stack)
        end

        defp convert_to_stack(0, acc), do: {acc, []}

        defp convert_to_stack(number, acc) do
          remainder = rem(number, 2)
          new_number = div(number, 2)
          convert_to_stack(new_number, [Integer.to_string(remainder) | acc])
        end
      end
      """,
      rule: PreferDirectListReturnInAccumulator,
      call: {:dec_to_bin_stack, 1},
      inputs: [0, 1, 5, 10, 255]
    )
  end
end
