defmodule Credence.Pattern.PreferIntegerUndigitsCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferIntegerUndigits

  describe "flags the anti-pattern" do
    test "detects Enum.reduce(digits, 0, fn digit, acc -> acc * 10 + digit end)" do
      code = """
      defmodule BadDigits do
        def to_number(digits) do
          Enum.reduce(digits, 0, fn digit, acc ->
            acc * 10 + digit
          end)
        end
      end
      """

      issues = check(PreferIntegerUndigits, code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_integer_undigits
    end

    test "detects commutative addition order (digit + acc * 10)" do
      code = """
      defmodule BadDigitsCommutative do
        def to_number(digits) do
          Enum.reduce(digits, 0, fn digit, acc ->
            digit + acc * 10
          end)
        end
      end
      """

      assert flagged?(PreferIntegerUndigits, code)
    end

    test "detects bare Enum.reduce without module prefix" do
      code = """
      Enum.reduce(list, 0, fn digit, acc -> acc * 10 + digit end)
      """

      assert flagged?(PreferIntegerUndigits, code)
    end

    test "detects multiple occurrences" do
      code = """
      defmodule Multiple do
        def process(a, b) do
          x = Enum.reduce(a, 0, fn d, acc -> acc * 10 + d end)
          y = Enum.reduce(b, 0, fn d, acc -> acc * 10 + d end)
          {x, y}
        end
      end
      """

      issues = check(PreferIntegerUndigits, code)
      assert length(issues) == 2
    end
  end

  describe "does NOT flag" do
    test "code that already uses Integer.undigits/1" do
      code = """
      defmodule GoodUndigits do
        def to_number(digits) do
          Integer.undigits(digits)
        end
      end
      """

      assert clean?(PreferIntegerUndigits, code)
    end

    test "sum reduction" do
      code = """
      defmodule GoodSum do
        def total(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert clean?(PreferIntegerUndigits, code)
    end

    test "product reduction" do
      code = """
      defmodule GoodProduct do
        def prod(list) do
          Enum.reduce(list, 1, fn x, acc -> acc * x end)
        end
      end
      """

      assert clean?(PreferIntegerUndigits, code)
    end

    test "reduce with non-0 initial accumulator" do
      code = """
      Enum.reduce(digits, 1, fn digit, acc -> acc * 10 + digit end)
      """

      assert clean?(PreferIntegerUndigits, code)
    end

    test "reduce with multiplier other than 10" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc -> acc * 100 + digit end)
      """

      assert clean?(PreferIntegerUndigits, code)
    end

    test "reduce where element is multiplied, not accumulator" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc -> digit * 10 + acc end)
      """

      assert clean?(PreferIntegerUndigits, code)
    end

    test "reduce with same param names" do
      code = """
      Enum.reduce(digits, 0, fn x, x -> x * 10 + x end)
      """

      assert clean?(PreferIntegerUndigits, code)
    end

    test "map-based reduction" do
      code = """
      defmodule GoodMap do
        def build(list) do
          Enum.reduce(list, %{}, fn x, acc -> Map.put(acc, x, true) end)
        end
      end
      """

      assert clean?(PreferIntegerUndigits, code)
    end

    test "multi-statement reducer body" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc ->
        y = digit
        acc * 10 + y
      end)
      """

      assert clean?(PreferIntegerUndigits, code)
    end
  end
end
