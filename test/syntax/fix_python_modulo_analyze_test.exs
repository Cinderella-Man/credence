defmodule Credence.Syntax.FixPythonModuloAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue

  defp analyze(code), do: Credence.Syntax.FixPythonModulo.analyze(code)

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — identifier % integer (the core LLM pattern)
  # ═══════════════════════════════════════════════════════════════════

  describe "flags identifier % integer" do
    test "year % 4" do
      assert [%Issue{rule: :python_modulo}] = analyze("year % 4")
    end

    test "n % 2" do
      assert [%Issue{}] = analyze("n % 2")
    end

    test "year % 100" do
      assert [%Issue{}] = analyze("year % 100")
    end

    test "year % 400" do
      assert [%Issue{}] = analyze("year % 400")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — identifier % identifier
  # ═══════════════════════════════════════════════════════════════════

  describe "flags identifier % identifier" do
    test "a % b" do
      assert [%Issue{}] = analyze("a % b")
    end

    test "n % divisor" do
      assert [%Issue{}] = analyze("n % divisor")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — integer % integer
  # ═══════════════════════════════════════════════════════════════════

  describe "flags integer % integer" do
    test "100 % 7" do
      assert [%Issue{}] = analyze("100 % 7")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — in comparisons (the classic even/odd check)
  # ═══════════════════════════════════════════════════════════════════

  describe "flags in comparisons" do
    test "n % 2 == 0" do
      assert [%Issue{}] = analyze("n % 2 == 0")
    end

    test "year % 4 != 0" do
      assert [%Issue{}] = analyze("year % 4 != 0")
    end

    test "n % 2 == 1" do
      assert [%Issue{}] = analyze("n % 2 == 1")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — in guards
  # ═══════════════════════════════════════════════════════════════════

  describe "flags in guards" do
    test "when year % 4 != 0" do
      assert [%Issue{}] = analyze("def leap?(year) when year % 4 != 0, do: false")
    end

    test "when n % 2 == 0" do
      assert [%Issue{}] = analyze("def even?(n) when n % 2 == 0, do: true")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — in assignments
  # ═══════════════════════════════════════════════════════════════════

  describe "flags in assignments" do
    test "remainder = n % 2" do
      assert [%Issue{}] = analyze("remainder = n % 2")
    end

    test "r = a % b" do
      assert [%Issue{}] = analyze("r = a % b")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — no spaces
  # ═══════════════════════════════════════════════════════════════════

  describe "flags without spaces" do
    test "n%2" do
      assert [%Issue{}] = analyze("n%2")
    end

    test "year%4" do
      assert [%Issue{}] = analyze("year%4")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — multiple on same line
  # ═══════════════════════════════════════════════════════════════════

  describe "flags multiple on same line" do
    test "tuple with three modulo ops" do
      assert [%Issue{}] = analyze("{year % 4, year % 100, year % 400}")
    end

    test "boolean expression with two modulo ops" do
      assert [%Issue{}] = analyze("year % 4 == 0 and year % 100 != 0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — multiple lines
  # ═══════════════════════════════════════════════════════════════════

  describe "flags multiple lines" do
    test "each line gets its own issue" do
      code = """
      def leap?(year) when year % 4 != 0, do: false
      def leap?(year) when year % 100 != 0, do: true
      def leap?(year) when year % 400 == 0, do: true
      """

      assert length(analyze(code)) == 3
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — in function body
  # ═══════════════════════════════════════════════════════════════════

  describe "flags in function body" do
    test "one-liner def" do
      assert [%Issue{}] = analyze("def even?(n), do: n % 2 == 0")
    end

    test "multi-line body" do
      code = """
      def fizzbuzz(n) do
        cond do
          n % 15 == 0 -> "FizzBuzz"
          n % 3 == 0 -> "Fizz"
          n % 5 == 0 -> "Buzz"
        end
      end
      """

      assert length(analyze(code)) == 3
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — map literals
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag map literals" do
    test "%{key: value}" do
      assert analyze("%{key: value}") == []
    end

    test "x = %{a: 1, b: 2}" do
      assert analyze("x = %{a: 1, b: 2}") == []
    end

    test "%{map | key: new_value}" do
      assert analyze("%{map | key: new_value}") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — struct literals
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag struct literals" do
    test "%MyStruct{field: value}" do
      assert analyze("%MyStruct{field: value}") == []
    end

    test "%__MODULE__{field: value}" do
      assert analyze("%__MODULE__{field: value}") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — already correct code
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag already correct code" do
    test "rem(n, 2)" do
      assert analyze("rem(n, 2)") == []
    end

    test "rem(year, 4) == 0" do
      assert analyze("rem(year, 4) == 0") == []
    end

    test "Integer.mod(n, 2)" do
      assert analyze("Integer.mod(n, 2)") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — other operators
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag other operators" do
    test "n / 2 (division)" do
      assert analyze("n / 2") == []
    end

    test "n * 2 (multiplication)" do
      assert analyze("n * 2") == []
    end

    test "n + 2 (addition)" do
      assert analyze("n + 2") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — comments
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag comments" do
    test "# n % 2" do
      assert analyze("# n % 2") == []
    end

    test "# remainder = year % 4" do
      assert analyze("  # remainder = year % 4") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — float operand (would break rem/2)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag float operand" do
    test "n % 2.0 (rem only works on integers)" do
      assert analyze("n % 2.0") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — no modulo at all
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag clean code" do
    test "plain arithmetic" do
      assert analyze("x = a + b * c") == []
    end

    test "function call" do
      assert analyze("Enum.map(list, &fun/1)") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # METADATA
  # ═══════════════════════════════════════════════════════════════════

  describe "metadata" do
    test "reports correct line number" do
      code = "x = 1\nremainder = n % 2\ny = 3"
      [issue] = analyze(code)
      assert issue.meta.line == 2
    end
  end
end
