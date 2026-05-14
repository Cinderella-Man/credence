defmodule Credence.Syntax.FixPythonModuloFixTest do
  use ExUnit.Case

  defp analyze(code), do: Credence.Syntax.FixPythonModulo.analyze(code)
  defp fix(code), do: Credence.Syntax.FixPythonModulo.fix(code)

  # ═══════════════════════════════════════════════════════════════════
  # BASIC — identifier % integer
  # ═══════════════════════════════════════════════════════════════════

  describe "identifier % integer" do
    test "year % 4 → rem(year, 4)" do
      assert fix("year % 4") == "rem(year, 4)"
    end

    test "n % 2 → rem(n, 2)" do
      assert fix("n % 2") == "rem(n, 2)"
    end

    test "year % 100 → rem(year, 100)" do
      assert fix("year % 100") == "rem(year, 100)"
    end

    test "year % 400 → rem(year, 400)" do
      assert fix("year % 400") == "rem(year, 400)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC — identifier % identifier
  # ═══════════════════════════════════════════════════════════════════

  describe "identifier % identifier" do
    test "a % b → rem(a, b)" do
      assert fix("a % b") == "rem(a, b)"
    end

    test "n % divisor → rem(n, divisor)" do
      assert fix("n % divisor") == "rem(n, divisor)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC — integer % integer
  # ═══════════════════════════════════════════════════════════════════

  describe "integer % integer" do
    test "100 % 7 → rem(100, 7)" do
      assert fix("100 % 7") == "rem(100, 7)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO SPACES
  # ═══════════════════════════════════════════════════════════════════

  describe "without spaces" do
    test "n%2 → rem(n, 2)" do
      assert fix("n%2") == "rem(n, 2)"
    end

    test "year%4 → rem(year, 4)" do
      assert fix("year%4") == "rem(year, 4)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # IN COMPARISONS
  # ═══════════════════════════════════════════════════════════════════

  describe "in comparisons" do
    test "n % 2 == 0 → rem(n, 2) == 0" do
      assert fix("n % 2 == 0") == "rem(n, 2) == 0"
    end

    test "year % 4 != 0 → rem(year, 4) != 0" do
      assert fix("year % 4 != 0") == "rem(year, 4) != 0"
    end

    test "n % 2 == 1 → rem(n, 2) == 1" do
      assert fix("n % 2 == 1") == "rem(n, 2) == 1"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # IN ASSIGNMENTS
  # ═══════════════════════════════════════════════════════════════════

  describe "in assignments" do
    test "remainder = n % 2 → remainder = rem(n, 2)" do
      assert fix("remainder = n % 2") == "remainder = rem(n, 2)"
    end

    test "r = a % b → r = rem(a, b)" do
      assert fix("r = a % b") == "r = rem(a, b)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE ON SAME LINE
  # ═══════════════════════════════════════════════════════════════════

  describe "multiple on same line" do
    test "tuple with three modulo ops" do
      assert fix("{year % 4, year % 100, year % 400}") ==
               "{rem(year, 4), rem(year, 100), rem(year, 400)}"
    end

    test "boolean expression" do
      assert fix("year % 4 == 0 and year % 100 != 0") ==
               "rem(year, 4) == 0 and rem(year, 100) != 0"
    end

    test "complex boolean with or" do
      assert fix("year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)") ==
               "rem(year, 4) == 0 and (rem(year, 100) != 0 or rem(year, 400) == 0)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # IN GUARDS
  # ═══════════════════════════════════════════════════════════════════

  describe "in guards" do
    test "when year % 4 != 0" do
      assert fix("def leap?(year) when year % 4 != 0, do: false") ==
               "def leap?(year) when rem(year, 4) != 0, do: false"
    end

    test "when n % 2 == 0" do
      assert fix("def even?(n) when n % 2 == 0, do: true") ==
               "def even?(n) when rem(n, 2) == 0, do: true"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REALISTIC — the actual LLM log case (test_00058 leap year)
  # ═══════════════════════════════════════════════════════════════════

  describe "realistic leap year (from log)" do
    test "multi-clause guard-based leap year" do
      input = """
      defmodule LeapYear do
        def leap_year?(year) when year % 4 != 0, do: false
        def leap_year?(year) when year % 100 != 0, do: true
        def leap_year?(year) when year % 400 == 0, do: true
        def leap_year?(_year), do: false
      end
      """

      expected = """
      defmodule LeapYear do
        def leap_year?(year) when rem(year, 4) != 0, do: false
        def leap_year?(year) when rem(year, 100) != 0, do: true
        def leap_year?(year) when rem(year, 400) == 0, do: true
        def leap_year?(_year), do: false
      end
      """

      assert fix(input) == expected
    end

    test "case-based leap year" do
      input = """
      def leap_year?(year) do
        case {year % 4, year % 100, year % 400} do
          {0, 0, 0} -> true
          {0, 0, _} -> false
          {0, _, _} -> true
          _ -> false
        end
      end
      """

      expected = """
      def leap_year?(year) do
        case {rem(year, 4), rem(year, 100), rem(year, 400)} do
          {0, 0, 0} -> true
          {0, 0, _} -> false
          {0, _, _} -> true
          _ -> false
        end
      end
      """

      assert fix(input) == expected
    end

    test "if-based leap year" do
      input = """
      def leap_year?(year) do
        year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
      end
      """

      expected = """
      def leap_year?(year) do
        rem(year, 4) == 0 and (rem(year, 100) != 0 or rem(year, 400) == 0)
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REALISTIC — fizzbuzz
  # ═══════════════════════════════════════════════════════════════════

  describe "realistic fizzbuzz" do
    test "cond-based fizzbuzz" do
      input = """
      def fizzbuzz(n) do
        cond do
          n % 15 == 0 -> "FizzBuzz"
          n % 3 == 0 -> "Fizz"
          n % 5 == 0 -> "Buzz"
          true -> to_string(n)
        end
      end
      """

      expected = """
      def fizzbuzz(n) do
        cond do
          rem(n, 15) == 0 -> "FizzBuzz"
          rem(n, 3) == 0 -> "Fizz"
          rem(n, 5) == 0 -> "Buzz"
          true -> to_string(n)
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REALISTIC — even/odd check
  # ═══════════════════════════════════════════════════════════════════

  describe "realistic even/odd" do
    test "one-liner even? predicate" do
      assert fix("def even?(n), do: n % 2 == 0") ==
               "def even?(n), do: rem(n, 2) == 0"
    end

    test "one-liner odd? predicate" do
      assert fix("def odd?(n), do: n % 2 != 0") ==
               "def odd?(n), do: rem(n, 2) != 0"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # PRESERVES SURROUNDING CODE
  # ═══════════════════════════════════════════════════════════════════

  describe "preserves surrounding code" do
    test "only touches lines with %" do
      input = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(n), do: n % 2 == 0
        def baz(y), do: y - 1
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(n), do: rem(n, 2) == 0
        def baz(y), do: y - 1
      end
      """

      assert fix(input) == expected
    end

    test "preserves indentation" do
      assert fix("      n % 2") == "      rem(n, 2)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — maps and structs
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch maps and structs" do
    test "map literal unchanged" do
      code = "%{key: value}"
      assert fix(code) == code
    end

    test "map in assignment unchanged" do
      code = "x = %{a: 1, b: 2}"
      assert fix(code) == code
    end

    test "map update unchanged" do
      code = "%{map | key: new_value}"
      assert fix(code) == code
    end

    test "struct literal unchanged" do
      code = "%MyStruct{field: value}"
      assert fix(code) == code
    end

    test "map pattern in function head unchanged" do
      code = "def foo(%{year: year}), do: year"
      assert fix(code) == code
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — already correct
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch already correct code" do
    test "rem(n, 2) unchanged" do
      code = "rem(n, 2)"
      assert fix(code) == code
    end

    test "Integer.mod(n, 2) unchanged" do
      code = "Integer.mod(n, 2)"
      assert fix(code) == code
    end

    test "no modulo at all" do
      code = "defmodule E do\n  def run(n), do: n + 1\nend\n"
      assert fix(code) == code
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — comments
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch comments" do
    test "comment with % unchanged" do
      code = "# n % 2 is the remainder"
      assert fix(code) == code
    end

    test "indented comment unchanged" do
      code = "  # year % 4 check"
      assert fix(code) == code
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — float operand (rem/2 only works on integers)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch float operand" do
    test "n % 2.0 unchanged" do
      code = "n % 2.0"
      assert fix(code) == code
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ROUND-TRIP
  # ═══════════════════════════════════════════════════════════════════

  describe "round-trip" do
    test "fixed code produces zero analyze issues" do
      code = """
      def leap?(year) when year % 4 != 0, do: false
      def even?(n), do: n % 2 == 0
      """

      assert analyze(fix(code)) == []
    end
  end
end
