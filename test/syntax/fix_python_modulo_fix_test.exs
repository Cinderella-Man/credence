defmodule Credence.Syntax.FixPythonModuloFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixPythonModulo
  defp analyze(code), do: FixPythonModulo.analyze(code)
  defp fix(code), do: FixPythonModulo.fix(code)

  # ═══════════════════════════════════════════════════════════════════
  # BASIC — identifier % integer
  # ═══════════════════════════════════════════════════════════════════

  describe "identifier % integer" do
    test "year % 4 → rem(year, 4)" do
      confirm_fix(fix("year % 4"), "rem(year, 4)")
    end

    test "n % 2 → rem(n, 2)" do
      confirm_fix(fix("n % 2"), "rem(n, 2)")
    end

    test "year % 100 → rem(year, 100)" do
      confirm_fix(fix("year % 100"), "rem(year, 100)")
    end

    test "year % 400 → rem(year, 400)" do
      confirm_fix(fix("year % 400"), "rem(year, 400)")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC — identifier % identifier
  # ═══════════════════════════════════════════════════════════════════

  describe "identifier % identifier" do
    test "a % b → rem(a, b)" do
      confirm_fix(fix("a % b"), "rem(a, b)")
    end

    test "n % divisor → rem(n, divisor)" do
      confirm_fix(fix("n % divisor"), "rem(n, divisor)")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BASIC — integer % integer
  # ═══════════════════════════════════════════════════════════════════

  describe "integer % integer" do
    test "100 % 7 → rem(100, 7)" do
      confirm_fix(fix("100 % 7"), "rem(100, 7)")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO SPACES
  # ═══════════════════════════════════════════════════════════════════

  describe "without spaces" do
    test "n%2 → rem(n, 2)" do
      confirm_fix(fix("n%2"), "rem(n, 2)")
    end

    test "year%4 → rem(year, 4)" do
      confirm_fix(fix("year%4"), "rem(year, 4)")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # IN COMPARISONS
  # ═══════════════════════════════════════════════════════════════════

  describe "in comparisons" do
    test "n % 2 == 0 → rem(n, 2) == 0" do
      confirm_fix(fix("n % 2 == 0"), "rem(n, 2) == 0")
    end

    test "year % 4 != 0 → rem(year, 4) != 0" do
      confirm_fix(fix("year % 4 != 0"), "rem(year, 4) != 0")
    end

    test "n % 2 == 1 → rem(n, 2) == 1" do
      confirm_fix(fix("n % 2 == 1"), "rem(n, 2) == 1")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # IN ASSIGNMENTS
  # ═══════════════════════════════════════════════════════════════════

  describe "in assignments" do
    test "remainder = n % 2 → remainder = rem(n, 2)" do
      confirm_fix(fix("remainder = n % 2"), "remainder = rem(n, 2)")
    end

    test "r = a % b → r = rem(a, b)" do
      confirm_fix(fix("r = a % b"), "r = rem(a, b)")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE ON SAME LINE
  # ═══════════════════════════════════════════════════════════════════

  describe "multiple on same line" do
    test "tuple with three modulo ops" do
      confirm_fix(
        fix("{year % 4, year % 100, year % 400}"),
        "{rem(year, 4), rem(year, 100), rem(year, 400)}"
      )
    end

    test "boolean expression" do
      confirm_fix(
        fix("year % 4 == 0 and year % 100 != 0"),
        "rem(year, 4) == 0 and rem(year, 100) != 0"
      )
    end

    test "complex boolean with or" do
      confirm_fix(
        fix("year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)"),
        "rem(year, 4) == 0 and (rem(year, 100) != 0 or rem(year, 400) == 0)"
      )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # IN GUARDS
  # ═══════════════════════════════════════════════════════════════════

  describe "in guards" do
    test "when year % 4 != 0" do
      confirm_fix(
        fix("def leap?(year) when year % 4 != 0, do: false"),
        "def leap?(year) when rem(year, 4) != 0, do: false"
      )
    end

    test "when n % 2 == 0" do
      confirm_fix(
        fix("def even?(n) when n % 2 == 0, do: true"),
        "def even?(n) when rem(n, 2) == 0, do: true"
      )
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

      confirm_fix(fix(input), expected)
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

      confirm_fix(fix(input), expected)
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

      confirm_fix(fix(input), expected)
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

      confirm_fix(fix(input), expected)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REALISTIC — even/odd check
  # ═══════════════════════════════════════════════════════════════════

  describe "realistic even/odd" do
    test "one-liner even? predicate" do
      confirm_fix(fix("def even?(n), do: n % 2 == 0"), "def even?(n), do: rem(n, 2) == 0")
    end

    test "one-liner odd? predicate" do
      confirm_fix(fix("def odd?(n), do: n % 2 != 0"), "def odd?(n), do: rem(n, 2) != 0")
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

      confirm_fix(fix(input), expected)
    end

    test "preserves indentation" do
      confirm_fix(fix("      n % 2"), "      rem(n, 2)")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — maps and structs
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch maps and structs" do
    test "map literal unchanged" do
      code = "%{key: value}"

      confirm_fix(fix(code), code)
    end

    test "map in assignment unchanged" do
      code = "x = %{a: 1, b: 2}"

      confirm_fix(fix(code), code)
    end

    test "map update unchanged" do
      code = "%{map | key: new_value}"

      confirm_fix(fix(code), code)
    end

    test "struct literal unchanged" do
      code = "%MyStruct{field: value}"

      confirm_fix(fix(code), code)
    end

    test "map pattern in function head unchanged" do
      code = "def foo(%{year: year}), do: year"

      confirm_fix(fix(code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — already correct
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch already correct code" do
    test "rem(n, 2) unchanged" do
      code = "rem(n, 2)"

      confirm_fix(fix(code), code)
    end

    test "Integer.mod(n, 2) unchanged" do
      code = "Integer.mod(n, 2)"

      confirm_fix(fix(code), code)
    end

    test "no modulo at all" do
      code = """
      defmodule E do
        def run(n), do: n + 1
      end

      """

      confirm_fix(fix(code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — comments
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch comments" do
    test "comment with % unchanged" do
      code = "# n % 2 is the remainder"

      confirm_fix(fix(code), code)
    end

    test "indented comment unchanged" do
      code = "  # year % 4 check"

      confirm_fix(fix(code), code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — float operand (rem/2 only works on integers)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch float operand" do
    test "n % 2.0 unchanged" do
      code = "n % 2.0"

      confirm_fix(fix(code), code)
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

  describe "fix output is well-formed" do
    test "fixed output parses" do
      assert valid_syntax?(fix("year % 4"))
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — a `%` inside a string is prose, not an operator
  #
  # Every case below shipped corrupted. The outputs parsed AND compiled,
  # so nothing downstream noticed the program had started printing
  # something the author never wrote.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — string literals are not code" do
    test "leaves a percentage inside a string alone" do
      confirm_fix(fix(~S'IO.puts("100% done")'), ~S'IO.puts("100% done")')
    end

    test "leaves the string alone while still fixing real code on the same line" do
      confirm_fix(
        fix(~S'IO.puts("50% left"); x = n % 2'),
        ~S'IO.puts("50% left"); x = rem(n, 2)'
      )
    end

    test "fixes inside interpolation — that IS code" do
      source = ~S'IO.puts("#{n % 2}")'
      expected = ~S'IO.puts("#{rem(n, 2)}")'
      confirm_fix(fix(source), expected)
    end

    test "leaves an uppercase sigil alone — it does not interpolate" do
      source = "IO.puts(~S(\#{n % 2}))"
      confirm_fix(fix(source), source)
    end

    test "leaves a trailing comment alone while fixing the code before it" do
      confirm_fix(fix("n % 2 # 50% note"), "rem(n, 2) # 50% note")
    end

    test "leaves a character-literal escape alone" do
      confirm_fix(fix("x = ?\\x41 % 2"), "x = ?\\x41 % 2")
    end

    test "does not report a string-only percent" do
      assert analyze(~S'IO.puts("100% done")') == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # STRUCT LITERALS — `%Name{}` in argument position
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — struct literals are not modulo" do
    test "leaves a struct literal in argument position alone" do
      confirm_fix(fix("assert %Issue{} = issue"), "assert %Issue{} = issue")
    end

    test "leaves a struct literal after a bare call alone" do
      confirm_fix(fix("x = foo %Bar{a: 1}"), "x = foo %Bar{a: 1}")
    end

    test "does not report a struct literal" do
      assert analyze("assert %Issue{} = issue") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # PRECEDENCE — Python's `%` shares precedence with `*` and `/`
  #
  # `a * b % 2` means `(a * b) % 2`. Emitting `a * rem(b, 2)` parses,
  # compiles, and computes a different number — so those lines are
  # declined and the parse error is left in place.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — precedence hazards are declined" do
    test "declines when the left operand follows `*`" do
      confirm_fix(fix("x = a * b % 2"), "x = a * b % 2")
    end

    test "declines when the left operand follows `/`" do
      confirm_fix(fix("x = a / b % 2"), "x = a / b % 2")
    end

    test "still fixes after `+`, which binds looser than `%` in Python" do
      confirm_fix(fix("x = a + b % 2"), "x = a + rem(b, 2)")
    end

    test "does not report a declined precedence hazard" do
      assert analyze("x = a * b % 2") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # END-TO-END through the syntax phase
  # ═══════════════════════════════════════════════════════════════════

  describe "integration through Credence.Syntax" do
    test "repairs the modulo without touching the percent strings" do
      source = """
      defmodule ModuloInteg do
        def render(n) do
          IO.puts("100% done")
          n % 2
        end
      end
      """

      expected = """
      defmodule ModuloInteg do
        def render(n) do
          IO.puts("100% done")
          rem(n, 2)
        end
      end
      """

      fixed = Credence.Syntax.fix(source)
      confirm_fix(fixed, expected)
      assert valid_syntax?(fixed)
    end
  end
end
