defmodule Credence.Pattern.PreferDirectListReturnInAccumulatorFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferDirectListReturnInAccumulator

  test "rewrites the anti-pattern" do
    input = """
    defmodule FixTest do
      def dec_to_bin_stack(number) do
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
    """

    expected = """
    defmodule FixTest do
      def dec_to_bin_stack(number) do
        stack = convert_to_stack(number, [])
        Enum.join(stack)
      end

      defp convert_to_stack(0, acc), do: acc

      defp convert_to_stack(number, acc) do
        remainder = rem(number, 2)
        new_number = div(number, 2)
        convert_to_stack(new_number, [Integer.to_string(remainder) | acc])
      end
    end
    """

    assert fix(PreferDirectListReturnInAccumulator, input) == expected
  end
end
