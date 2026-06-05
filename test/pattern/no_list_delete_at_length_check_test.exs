defmodule Credence.Pattern.NoListDeleteAtLengthCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoListDeleteAtLength

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListDeleteAtLength.check(ast, [])
  end

  describe "flags delete-the-last-element via length" do
    test "bare call with length(x) - 1" do
      assert [%Issue{rule: :no_list_delete_at_length}] =
               check("List.delete_at(list, length(list) - 1)")
    end

    test "Kernel.length/1 form" do
      assert [%Issue{rule: :no_list_delete_at_length}] =
               check("List.delete_at(list, Kernel.length(list) - 1)")
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

      assert [%Issue{rule: :no_list_delete_at_length}] = check(code)
    end
  end

  describe "does NOT flag" do
    # length(x) - K differs from -K for short lists when K >= 2:
    # for length(x) < K the left form yields a negative index that still
    # deletes from the end, while -K is out of range and deletes nothing.
    # No constant-index rewrite is behaviour-preserving, so K >= 2 is dropped.
    test "length(x) - 2 (offset other than 1)" do
      assert check("List.delete_at(list, length(list) - 2)") == []
    end

    test "length(x) - 3 (offset other than 1)" do
      assert check("List.delete_at(list, length(list) - 3)") == []
    end

    test "different variable's length" do
      assert check("List.delete_at(list, length(other) - 1)") == []
    end

    test "literal index" do
      assert check("List.delete_at(list, 0)") == []
    end

    test "variable index" do
      assert check("List.delete_at(list, idx)") == []
    end

    test "already negative literal index" do
      assert check("List.delete_at(list, -1)") == []
    end

    test "Enum.at with length (covered by no_length_based_indexing)" do
      assert check("Enum.at(list, length(list) - 1)") == []
    end

    test "addition rather than subtraction" do
      assert check("List.delete_at(list, length(list) + 1)") == []
    end
  end
end
