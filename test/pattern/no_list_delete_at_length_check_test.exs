defmodule Credence.Pattern.NoListDeleteAtLengthCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoListDeleteAtLength

  describe "flags delete-the-last-element via length" do
    test "bare call with length(x) - 1" do
      assert [%Issue{rule: :no_list_delete_at_length}] =
               check(NoListDeleteAtLength, "List.delete_at(list, length(list) - 1)")
    end

    test "Kernel.length/1 form" do
      assert [%Issue{rule: :no_list_delete_at_length}] =
               check(NoListDeleteAtLength, "List.delete_at(list, Kernel.length(list) - 1)")
    end

    test "the pattern from the row log" do
      code = """
      defmodule Solution do
        def swap_head_tail(list) do
          [head | tail] = list
          last = List.last(tail)
          middle = List.delete_at(tail, length(tail) - 1)
          [last | middle] ++ [head]
        end
      end
      """

      assert [%Issue{rule: :no_list_delete_at_length}] = check(NoListDeleteAtLength, code)
    end
  end

  describe "does NOT flag" do
    # length(x) - K differs from -K for short lists when K >= 2:
    # for length(x) < K the left form yields a negative index that still
    # deletes from the end, while -K is out of range and deletes nothing.
    # No constant-index rewrite is behaviour-preserving, so K >= 2 is dropped.
    test "length(x) - 2 (offset other than 1)" do
      assert check(NoListDeleteAtLength, "List.delete_at(list, length(list) - 2)") == []
    end

    test "length(x) - 3 (offset other than 1)" do
      assert check(NoListDeleteAtLength, "List.delete_at(list, length(list) - 3)") == []
    end

    test "different variable's length" do
      assert check(NoListDeleteAtLength, "List.delete_at(list, length(other) - 1)") == []
    end

    test "literal index" do
      assert check(NoListDeleteAtLength, "List.delete_at(list, 0)") == []
    end

    test "variable index" do
      assert check(NoListDeleteAtLength, "List.delete_at(list, idx)") == []
    end

    test "already negative literal index" do
      assert check(NoListDeleteAtLength, "List.delete_at(list, -1)") == []
    end

    test "Enum.at with length (covered by no_length_based_indexing)" do
      assert check(NoListDeleteAtLength, "Enum.at(list, length(list) - 1)") == []
    end

    test "addition rather than subtraction" do
      assert check(NoListDeleteAtLength, "List.delete_at(list, length(list) + 1)") == []
    end
  end

  # Ported from `no_list_delete_at_with_length`, retired 2026-08-16 as an exact
  # duplicate of this rule (same target, same repair, identical coverage on
  # every shape probed). Deleting a rule is only safe while its behaviour is
  # pinned somewhere else — this is that somewhere, and it is the one assertion
  # the retired rule had that this file did not: the issue reaches
  # `Credence.Pattern.analyze/1`, not just `check/2`.
  test "the anti-pattern is reported through Pattern.analyze/1" do
    source = """
    defmodule DropsLast do
      def drop_last(list) do
        List.delete_at(list, length(list) - 1)
      end
    end
    """

    found =
      source
      |> Credence.Pattern.analyze()
      |> Enum.filter(&(&1.rule == :no_list_delete_at_length))

    assert length(found) == 1
  end
end
