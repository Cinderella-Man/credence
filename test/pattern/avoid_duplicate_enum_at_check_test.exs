defmodule Credence.Pattern.AvoidDuplicateEnumAtCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidDuplicateEnumAt

  describe "flags the anti-pattern" do
    test "two Enum.at calls on the same list with > comparison" do
      assert flagged?(AvoidDuplicateEnumAt, """
             if Enum.at(nums, mid) > Enum.at(nums, high) do
               :left
             else
               :right
             end
             """)
    end

    test "two Enum.at calls on the same list with < comparison" do
      assert flagged?(AvoidDuplicateEnumAt, """
             if Enum.at(nums, a) < Enum.at(nums, b) do
               :left
             else
               :right
             end
             """)
    end

    test "two Enum.at calls with >= comparison" do
      assert flagged?(AvoidDuplicateEnumAt, """
             if Enum.at(list, x) >= Enum.at(list, y) do
               :yes
             else
               :no
             end
             """)
    end

    test "inside a module function" do
      code = """
      defmodule Example do
        def run(nums, mid, high) do
          if Enum.at(nums, mid) > Enum.at(nums, high) do
            :left
          else
            :right
          end
        end
      end
      """

      assert flagged?(AvoidDuplicateEnumAt, code)
    end
  end

  describe "does NOT flag" do
    test "single Enum.at call in condition" do
      assert clean?(AvoidDuplicateEnumAt, """
             if Enum.at(nums, mid) > 0 do
               :left
             else
               :right
             end
             """)
    end

    test "two Enum.at calls on different lists" do
      assert clean?(AvoidDuplicateEnumAt, """
             if Enum.at(nums1, mid) > Enum.at(nums2, high) do
               :left
             else
               :right
             end
             """)
    end

    test "Enum.at calls outside of if condition" do
      assert clean?(AvoidDuplicateEnumAt, """
             x = Enum.at(nums, mid)
             y = Enum.at(nums, high)
             """)
    end

    test "single Enum.at with non-variable list" do
      assert clean?(AvoidDuplicateEnumAt, """
             if Enum.at(foo(), mid) > 0 do
               :yes
             else
               :no
             end
             """)
    end
  end
end
