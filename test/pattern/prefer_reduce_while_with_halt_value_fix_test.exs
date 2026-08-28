defmodule Credence.Pattern.PreferReduceWhileWithHaltValueFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferReduceWhileWithHaltValue
  alias Credence.RuleHelpers

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

    confirm_fix(fix(PreferReduceWhileWithHaltValue, input), expected)
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

    confirm_fix(fix(PreferReduceWhileWithHaltValue, code), code)
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

  test "does not remove a callback flag that the body reads" do
    code = """
    defmodule PreferReduceWhileUsedFlagFixture do
      def check(list) do
        {_a, _b, found?} =
          Enum.reduce_while(list, {0, 0, false}, fn x, {a, b, flag} ->
            if flag or x > 0 do
              {:halt, {a, b, true}}
            else
              {:cont, {a + x, b, false}}
            end
          end)

        found?
      end
    end
    """

    emitted = fix(PreferReduceWhileWithHaltValue, code)
    confirm_fix(emitted, code)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(emitted)
  end

  test "does not discard evaluation of halt accumulator expressions" do
    code = """
    defmodule PreferReduceWhileHaltEvaluationFixture do
      def check(list) do
        {_a, _b, found?} =
          Enum.reduce_while(list, {0, 0, false}, fn x, {a, b, _flag} ->
            if x > 0 do
              {:halt, {raise("evaluated first"), b, true}}
            else
              {:cont, {a, b, false}}
            end
          end)

        found?
      end
    end
    """

    emitted = fix(PreferReduceWhileWithHaltValue, code)
    confirm_fix(emitted, code)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(emitted)
  end

  test "does not rewrite an if that is not the callback result" do
    code = """
    defmodule PreferReduceWhileTrailingResultFixture do
      def check(list) do
        {_a, _b, found?} =
          Enum.reduce_while(list, {0, 0, false}, fn x, {a, b, _flag} ->
            if x > 0 do
              {:halt, {a, b, true}}
            else
              {:cont, {a, b, false}}
            end

            {:cont, {a + x, b, false}}
          end)

        found?
      end
    end
    """

    emitted = fix(PreferReduceWhileWithHaltValue, code)
    confirm_fix(emitted, code)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(emitted)
  end

  test "leaves a dynamic halt flag unchanged instead of crashing" do
    code = """
    defmodule PreferReduceWhileDynamicFlagFixture do
      def check(list) do
        {_a, _b, found?} =
          Enum.reduce_while(list, {0, 0, false}, fn x, {a, b, flag} ->
            if x > 0 do
              {:halt, {a, b, flag}}
            else
              {:cont, {a, b, false}}
            end
          end)

        found?
      end
    end
    """

    confirm_fix(fix(PreferReduceWhileWithHaltValue, code), code)
  end
end
