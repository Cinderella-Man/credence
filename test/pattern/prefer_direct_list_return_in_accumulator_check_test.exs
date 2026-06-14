defmodule Credence.Pattern.PreferDirectListReturnInAccumulatorCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferDirectListReturnInAccumulator

  test "flags the anti-pattern: base case returns {acc, []} and caller discards second element" do
    assert flagged?(PreferDirectListReturnInAccumulator, """
           defmodule CheckFlagged do
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
           """)
  end

  test "leaves good code alone: already returns just the accumulator" do
    assert clean?(PreferDirectListReturnInAccumulator, """
           defmodule CheckClean do
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
           """)
  end

  test "leaves code alone when base case returns a non-empty-list tuple" do
    assert clean?(PreferDirectListReturnInAccumulator, """
           defmodule CheckNonEmptyTuple do
             def build(number) do
               {result, _} = do_build(number, [])
               result
             end

             defp do_build(0, acc), do: {acc, [0]}

             defp do_build(n, acc) do
               do_build(n - 1, [n | acc])
             end
           end
           """)
  end

  test "leaves code alone when caller uses both tuple elements" do
    assert clean?(PreferDirectListReturnInAccumulator, """
           defmodule CheckBothUsed do
             def build(number) do
               {result, remainder} = do_build(number, [])
               {result, remainder}
             end

             defp do_build(0, acc), do: {acc, []}

             defp do_build(n, acc) do
               do_build(n - 1, [n | acc])
             end
           end
           """)
  end
end
