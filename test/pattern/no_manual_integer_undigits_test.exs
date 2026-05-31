defmodule Credence.Pattern.NoManualIntegerUndigitsTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualIntegerUndigits

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualIntegerUndigits.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoManualIntegerUndigits, code, [])

  describe "check" do
    test "passes code that already uses Integer.undigits/2" do
      code = """
      defmodule GoodUndigits do
        def to_decimal(digits) do
          Integer.undigits(digits, 2)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.reduce with acc * 2 + digit (binary)" do
      code = """
      defmodule BadBinary do
        def to_decimal(digits) do
          Enum.reduce(digits, 0, fn digit, acc -> acc * 2 + digit end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_manual_integer_undigits
    end

    test "detects Enum.reduce with digit + acc * 10 (decimal, commutative add)" do
      code = """
      defmodule BadDecimal do
        def to_decimal(digits) do
          Enum.reduce(digits, 0, fn digit, acc -> digit + acc * 10 end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects Enum.reduce with base * acc + digit (commutative mul)" do
      code = """
      defmodule BadCommutativeMul do
        def to_decimal(digits) do
          Enum.reduce(digits, 0, fn digit, acc -> 2 * acc + digit end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects pipeline form" do
      code = """
      defmodule BadPipeline do
        def to_decimal(digits) do
          digits
          |> Enum.reduce(0, fn digit, acc -> acc * 2 + digit end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT detect reduce with non-zero initial accumulator" do
      code = """
      defmodule GoodNonZero do
        def to_decimal(digits) do
          Enum.reduce(digits, 1, fn digit, acc -> acc * 2 + digit end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect reduce with non-literal base" do
      code = """
      defmodule GoodNonLiteralBase do
        def to_decimal(digits, base) do
          Enum.reduce(digits, 0, fn digit, acc -> acc * base + digit end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect reduce with unrelated accumulator logic" do
      code = """
      defmodule GoodOtherReduce do
        def process(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect reduce with base <= 1" do
      code = """
      defmodule GoodBaseOne do
        def weird(list) do
          Enum.reduce(list, 0, fn x, acc -> acc * 1 + x end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.join() |> String.to_integer() in pipeline" do
      code = """
      defmodule BadJoinPipeline do
        def to_number(digits) do
          digits
          |> Enum.join()
          |> String.to_integer()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_manual_integer_undigits
    end

    test "detects Enum.join(\"\") |> String.to_integer() in pipeline" do
      code = """
      defmodule BadJoinEmptySep do
        def to_number(digits) do
          digits
          |> Enum.join("")
          |> String.to_integer()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects String.to_integer(Enum.join(list)) nested" do
      code = """
      defmodule BadJoinNested do
        def to_number(digits) do
          String.to_integer(Enum.join(digits))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects String.to_integer(Enum.join(list, \"\")) nested" do
      code = """
      defmodule BadJoinNestedEmpty do
        def to_number(digits) do
          String.to_integer(Enum.join(digits, ""))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT detect Enum.join with non-empty separator" do
      code = """
      defmodule GoodJoinSep do
        def to_string(list) do
          list
          |> Enum.join(", ")
          |> String.to_integer()
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect Enum.join with non-empty separator (nested)" do
      code = """
      defmodule GoodJoinSepNested do
        def to_string(list) do
          String.to_integer(Enum.join(list, "-"))
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces reduce with Integer.undigits/2 (direct call)" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc -> acc * 2 + digit end)
      """

      result = fix(code)
      assert result =~ "Integer.undigits(digits, 2)"
      refute result =~ "Enum.reduce"
    end

    test "replaces reduce with Integer.undigits/2 (pipeline)" do
      code = """
      digits
      |> Enum.reduce(0, fn digit, acc -> acc * 2 + digit end)
      """

      result = fix(code)
      assert result =~ "Integer.undigits(2)"
      assert result =~ "digits"
      refute result =~ "Enum.reduce"
    end

    test "handles decimal base" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc -> acc * 10 + digit end)
      """

      result = fix(code)
      assert result =~ "Integer.undigits(digits, 10)"
    end

    test "handles commutative operand order" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc -> digit + acc * 2 end)
      """

      result = fix(code)
      assert result =~ "Integer.undigits(digits, 2)"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def convert(digits) do
          prefix = "0b"
          value = Enum.reduce(digits, 0, fn digit, acc -> acc * 2 + digit end)
          {prefix, value}
        end
      end
      """

      result = fix(code)
      assert result =~ "prefix"
      assert result =~ "Integer.undigits(digits, 2)"
      assert result =~ "{prefix, value}"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc -> acc * 2 + digit end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoManualIntegerUndigits.check(ast, []) == []
    end

    test "replaces Enum.join() |> String.to_integer() with Integer.undigits()" do
      code = """
      digits
      |> Enum.join()
      |> String.to_integer()
      """

      result = fix(code)
      assert result =~ "Integer.undigits()"
      assert result =~ "digits"
      refute result =~ "Enum.join"
      refute result =~ "String.to_integer"
    end

    test "replaces String.to_integer(Enum.join(list)) with Integer.undigits(list)" do
      code = """
      String.to_integer(Enum.join(digits))
      """

      result = fix(code)
      assert result =~ "Integer.undigits(digits)"
      refute result =~ "Enum.join"
      refute result =~ "String.to_integer"
    end

    test "replaces Enum.join(list, \"\") |> String.to_integer() with Integer.undigits(list)" do
      code = """
      digits
      |> Enum.join("")
      |> String.to_integer()
      """

      result = fix(code)
      assert result =~ "Integer.undigits()"
      assert result =~ "digits"
      refute result =~ "Enum.join"
      refute result =~ "String.to_integer"
    end

    test "replaces String.to_integer(Enum.join(list, \"\")) with Integer.undigits(list)" do
      code = """
      String.to_integer(Enum.join(digits, ""))
      """

      result = fix(code)
      assert result =~ "Integer.undigits(digits)"
      refute result =~ "Enum.join"
    end

    test "join pattern round-trip: fixed code produces no issues" do
      code = """
      defmodule M do
        def to_number(digits) do
          digits
          |> Enum.join()
          |> String.to_integer()
        end
      end
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoManualIntegerUndigits.check(ast, []) == []
    end
  end
end
