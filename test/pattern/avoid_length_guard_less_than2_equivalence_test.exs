defmodule Credence.Pattern.AvoidLengthGuardLessThan2EquivalenceTest do
  @moduledoc """
  T2 module-call. `def maximumdifference(list) when length(list) < 2, do: 0`
  → two clauses `def maximumdifference([]), do: 0` / `def maximumdifference([_]), do: 0`.

  Both paths return 0 for lists of length 0 or 1, and delegate to the
  `[head | tail]` clause for longer lists. The fix preserves the exact
  same return values for every list input.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.AvoidLengthGuardLessThan2

  test "length < 2 guard → pattern match preserves behaviour" do
    assert_equivalent_module(
      """
      defmodule MaximumDiffBefore do
        def maximumdifference(list) when length(list) < 2, do: 0

        def maximumdifference([head | tail]) do
          do_maximumdifference(tail, head, 0)
        end

        defp do_maximumdifference([], _min_so_far, max_diff), do: max_diff

        defp do_maximumdifference([current | rest], min_so_far, max_diff) do
          current_diff = current - min_so_far
          new_max_diff = max(max_diff, current_diff)
          new_min_so_far = min(min_so_far, current)
          do_maximumdifference(rest, new_min_so_far, new_max_diff)
        end
      end
      """,
      rule: AvoidLengthGuardLessThan2,
      call: {:maximumdifference, 1},
      inputs: [
        [],
        [1],
        [1, 2],
        [3, 1, 2],
        [1, 2, 3, 4, 5],
        [5, 4, 3, 2, 1],
        [1, 1.0, 1, 1.0, 2],
        Enum.map(1..200, fn i -> rem(i, 7) end)
      ]
    )
  end

  test "nested parameter pattern preserves behaviour" do
    assert_equivalent_module(
      """
      defmodule AvoidLengthNestedEquivalence do
        def f({list}) when length(list) < 2, do: {:accepted, list}
      end
      """,
      rule: AvoidLengthGuardLessThan2,
      call: {:f, 1},
      inputs: [{[]}, {[1]}, {[1, 2]}]
    )
  end

  test "repeated guarded variable preserves head equality" do
    assert_equivalent_module(
      """
      defmodule AvoidLengthRepeatedEquivalence do
        def f(list, list) when length(list) < 2, do: {:accepted, list}
      end
      """,
      rule: AvoidLengthGuardLessThan2,
      call: {:f, 2},
      inputs: [{[], []}, {[1], [1]}, {[1], [2]}, {[], [1]}, {[1, 2], [1, 2]}]
    )
  end
end
