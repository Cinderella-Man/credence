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

    # ── Deliberately out of the safe core (would diverge if fixed) ──────

    test "ignores accumulators larger than 3 elements (case arity would crash)" do
      # Dropping the flag leaves a 3-tuple, but the generated `case` only
      # matches `{_, _}`; a non-halting run would raise CaseClauseError.
      code = """
      defmodule Solution do
        def check(list) do
          {_a, _b, _c, found?} =
            Enum.reduce_while(list, {0, 0, MapSet.new([0]), false}, fn num, {x, y, ss, _f} ->
              new_sum = x + num

              if MapSet.member?(ss, new_sum) do
                {:halt, {new_sum, y, ss, true}}
              else
                {:cont, {new_sum, y, MapSet.put(ss, new_sum), false}}
              end
            end)

          found?
        end
      end
      """

      assert clean?(PreferReduceWhileWithHaltValue, code)
    end

    test "ignores a `true` initial flag (would diverge on an empty list)" do
      # On `[]` the original returns the seed flag `true`; the fix returns
      # `false`, so this is not a safe rewrite.
      code = """
      defmodule Solution do
        def check(list) do
          {_a, _b, found?} =
            Enum.reduce_while(list, {0, MapSet.new([0]), true}, fn num, {ps, ss, _f} ->
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

      assert clean?(PreferReduceWhileWithHaltValue, code)
    end

    test "ignores a reduce_while whose result is not extracted as `{_, _, flag}; flag`" do
      # `check` must agree with `fix`: without the extraction-and-return block
      # the fix cannot transform anything, so nothing is flagged.
      code = """
      defmodule Solution do
        def check(list) do
          result =
            Enum.reduce_while(list, {0, MapSet.new([0]), false}, fn num, {ps, ss, _f} ->
              new_sum = ps + num

              if MapSet.member?(ss, new_sum) do
                {:halt, {new_sum, ss, true}}
              else
                {:cont, {new_sum, MapSet.put(ss, new_sum), false}}
              end
            end)

          elem(result, 2)
        end
      end
      """

      assert clean?(PreferReduceWhileWithHaltValue, code)
    end

    test "ignores a non-`_` leading binding (conservatively stays in safe core)" do
      code = """
      defmodule Solution do
        def check(list) do
          {prefix_sum, _ss, found?} =
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

      assert clean?(PreferReduceWhileWithHaltValue, code)
    end
  end
end
