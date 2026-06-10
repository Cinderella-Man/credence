defmodule Credence.Pattern.PreferReduceWhileWithHaltValueFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferReduceWhileWithHaltValue

  test "rewrites the anti-pattern" do
    input = """
    defmodule Solution do
      @spec check_zero_subarray(list(integer())) :: boolean()
      def check_zero_subarray([]), do: false

      def check_zero_subarray(list) do
        {_prefix_sum, _seen_sums, found?} =
          Enum.reduce_while(
            list,
            {0, MapSet.new([0]), false},
            fn num, {prefix_sum, seen_sums, _found} ->
              new_sum = prefix_sum + num

              if MapSet.member?(seen_sums, new_sum) do
                {:halt, {new_sum, seen_sums, true}}
              else
                {:cont, {new_sum, MapSet.put(seen_sums, new_sum), false}}
              end
            end
          )

        found?
      end
    end
    """

    expected = """
    defmodule Solution do
      @spec check_zero_subarray(list(integer())) :: boolean()
      def check_zero_subarray([]), do: false

      def check_zero_subarray(list) do
        Enum.reduce_while(
          list,
          {0, MapSet.new([0])},
          fn num, {prefix_sum, seen_sums} ->
            new_sum = prefix_sum + num

            if MapSet.member?(seen_sums, new_sum) do
              {:halt, true}
            else
              {:cont, {new_sum, MapSet.put(seen_sums, new_sum)}}
            end
          end
        )
        |> case do
          true -> true
          {_, _} -> false
        end
      end
    end
    """

    assert fix(PreferReduceWhileWithHaltValue, input) == expected
  end

  test "does not modify code without the anti-pattern" do
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

    assert fix(PreferReduceWhileWithHaltValue, code) == code
  end

  test "round-trip: fixed code produces no issues" do
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

    fixed = fix(PreferReduceWhileWithHaltValue, code)
    assert clean?(PreferReduceWhileWithHaltValue, fixed)
  end
end
