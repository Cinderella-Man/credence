defmodule Credence.Pattern.NoListDeleteAtLengthFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListDeleteAtLength

  describe "rewrites length(x) - 1 to the constant -1" do
    test "bare call" do
      assert fix(NoListDeleteAtLength, """
             List.delete_at(list, length(list) - 1)
             """) ==
               """
               List.delete_at(list, -1)
               """
    end

    test "Kernel.length/1 form" do
      assert fix(NoListDeleteAtLength, """
             List.delete_at(list, Kernel.length(list) - 1)
             """) ==
               """
               List.delete_at(list, -1)
               """
    end

    test "inside a function body" do
      code = """
      defmodule M do
        def drop_last(list) do
          List.delete_at(list, length(list) - 1)
        end
      end
      """

      expected = """
      defmodule M do
        def drop_last(list) do
          List.delete_at(list, -1)
        end
      end
      """

      assert fix(NoListDeleteAtLength, code) == expected
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

      expected = """
      defmodule Solution do
        def swap_head_tail(list) do
          [head | tail] = list
          last = List.last(tail)
          middle = List.delete_at(tail, -1)
          [last | middle] ++ [head]
        end
      end
      """

      assert fix(NoListDeleteAtLength, code) == expected
    end
  end

  describe "no-ops" do
    test "offset of 2 is left untouched" do
      code = """
      List.delete_at(list, length(list) - 2)
      """

      assert fix(NoListDeleteAtLength, code) == code
    end

    test "different variable's length is left untouched" do
      code = """
      List.delete_at(list, length(other) - 1)
      """

      assert fix(NoListDeleteAtLength, code) == code
    end

    test "already negative literal index is left untouched" do
      code = """
      List.delete_at(list, -1)
      """

      assert fix(NoListDeleteAtLength, code) == code
    end

    test "literal index is left untouched" do
      code = """
      List.delete_at(list, 0)
      """

      assert fix(NoListDeleteAtLength, code) == code
    end
  end

  describe "round-trip" do
    test "fixed code produces zero issues" do
      assert check(
               NoListDeleteAtLength,
               fix(NoListDeleteAtLength, """
               List.delete_at(list, length(list) - 1)
               """)
             ) == []
    end

    test "fixed code is valid Elixir" do
      assert valid_syntax?(
               fix(NoListDeleteAtLength, """
               List.delete_at(list, length(list) - 1)
               """)
             )
    end
  end
end
