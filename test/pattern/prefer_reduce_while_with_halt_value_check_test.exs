defmodule Credence.Pattern.PreferReduceWhileWithHaltValueCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferReduceWhileWithHaltValue

  describe "fires" do
    test "flags the anti-pattern with boolean flag in accumulator" do
      code = """
      defmodule Solution do
        def check(list) do
          {_ps, _ss, found?} =
            Enum.reduce_while(list, {0, MapSet.new([0]), false}, fn num, {ps, ss, _f} ->
              new_sum = ps + num

              if MapSet.member?(ss, new_sum) do
                {:halt, {new_sum, ss, true}}
              else
                {:cont, {new_sum, MapSet.put(ss, new_sum), false}}
              end
            end)

          found?
        end
      end
      """

      assert flagged?(PreferReduceWhileWithHaltValue, code)
    end
  end

  describe "no issue" do
    test "leaves good code alone (halt value without boolean flag)" do
      code = """
      defmodule Solution do
        def check(list) do
          Enum.reduce_while(list, {0, MapSet.new([0])}, fn num, {ps, ss} ->
            new_sum = ps + num

            if MapSet.member?(ss, new_sum) do
              {:halt, true}
            else
              {:cont, {new_sum, MapSet.put(ss, new_sum)}}
            end
          end)
          |> case do
            true -> true
            {_, _} -> false
          end
        end
      end
      """

      assert clean?(PreferReduceWhileWithHaltValue, code)
    end

    test "leaves plain reduce_while alone" do
      code = """
      defmodule Solution do
        def total(list) do
          Enum.reduce_while(list, 0, fn x, acc ->
            {:cont, acc + x}
          end)
        end
      end
      """

      assert clean?(PreferReduceWhileWithHaltValue, code)
    end

    test "leaves reduce_while with proper halt alone" do
      code = """
      defmodule Solution do
        def find_negative(list) do
          Enum.reduce_while(list, 0, fn x, acc ->
            if x < 0, do: {:halt, acc}, else: {:cont, acc + x}
          end)
        end
      end
      """

      assert clean?(PreferReduceWhileWithHaltValue, code)
    end
  end
end
