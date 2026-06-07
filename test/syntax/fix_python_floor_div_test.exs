defmodule Credence.Syntax.FixPythonFloorDivTest do
  use ExUnit.Case

  alias Credence.Syntax.FixPythonFloorDiv

  defp analyze(code), do: FixPythonFloorDiv.analyze(code)
  defp fix(code), do: FixPythonFloorDiv.fix(code)

  # ═══════════════════════════════════════════════════════════════════
  # analyze/1 — what is flagged
  # ═══════════════════════════════════════════════════════════════════

  describe "analyze/1 flags floor division" do
    test "infix word // word" do
      issues = analyze("def half(n), do: n // 2")
      assert length(issues) == 1
      assert hd(issues).rule == :python_floor_div
      assert hd(issues).meta == %{line: 1}
    end

    test "Kernel.// in pipe" do
      source = """
      defmodule Example do
        def step(acc, k) do
          acc
          |> Kernel.//(k)
          |> next()
        end
      end
      """

      issues = analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :python_floor_div
    end

    test "Kernel.// standalone call" do
      assert length(analyze("def divide(a, b), do: Kernel.//(a, b)")) == 1
    end
  end

  describe "analyze/1 — deliberately NOT flagged (dropped from the safe core)" do
    # A parenthesised left operand cannot be rewritten safely without a parser,
    # so it is left untouched. check and fix agree: neither touches it.
    test "no issue for `(expr) // n` (complex left operand)" do
      source = """
      defmodule Example do
        def gauss(n) do
          result = n * (n + 1) // 2
          result
        end
      end
      """

      assert analyze(source) == []
    end

    test "no issue for valid div/2 call" do
      assert analyze("def half(n), do: div(n, 2)") == []
    end

    test "no issue for pipe into div" do
      assert analyze("def half(n), do: n |> div(2)") == []
    end

    test "no issue for // inside a comment" do
      source = """
      defmodule Example do
        # use integer division (// in Python)
        def half(n), do: div(n, 2)
      end
      """

      assert analyze(source) == []
    end

    test "no issue for Kernel./ float division" do
      assert analyze("def half(n), do: Kernel./(n, 2)") == []
    end

    test "no issue for range step 0..-2//1" do
      assert analyze("Enum.slice(list, 0..-2//1)") == []
    end

    test "no issue for range step 1..10//2" do
      assert analyze("Enum.to_list(1..10//2)") == []
    end

    test "no issue for range step with variable bounds n..m//-1" do
      assert analyze("Enum.to_list(n..m//-1)") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # fix/1 — exact whole-string rewrites
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 rewrites word // word to div" do
    test "n // 2" do
      assert fix("n // 2") == "div(n, 2)"
    end

    test "no spaces n//2" do
      assert fix("n//2") == "div(n, 2)"
    end

    test "integer // integer" do
      assert fix("100 // 7") == "div(100, 7)"
    end

    test "in assignment" do
      assert fix("x = a // b") == "x = div(a, b)"
    end
  end

  describe "fix/1 preserves surrounding code (local swap)" do
    test "one-liner def head" do
      assert fix("def half(n), do: n // 2") == "def half(n), do: div(n, 2)"
    end

    test "comparison / guard context" do
      assert fix("if n // 2 == 0 do") == "if div(n, 2) == 0 do"
    end

    test "preserves indentation" do
      assert fix("      n // 2") == "      div(n, 2)"
    end

    test "only touches lines with floor division" do
      input = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(n), do: n // 2
        def baz(y), do: y - 1
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar(n), do: div(n, 2)
        def baz(y), do: y - 1
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fix/1 rewrites Kernel.//" do
    test "standalone call" do
      assert fix("result = Kernel.//(a, b)") == "result = div(a, b)"
    end

    test "in pipe" do
      input = """
      defmodule Example do
        def step(acc, k) do
          acc
          |> Kernel.//(k)
          |> next()
        end
      end
      """

      expected = """
      defmodule Example do
        def step(acc, k) do
          acc
          |> div(k)
          |> next()
        end
      end
      """

      assert fix(input) == expected
    end

    test "the exact pattern from the row log — only Kernel.// is touched" do
      input = """
      defp do_combination(n, k, acc) do
        acc
        |> Kernel.*(n - k + 1)
        |> Kernel.//(k)
        |> do_combination(n, k - 1)
      end
      """

      expected = """
      defp do_combination(n, k, acc) do
        acc
        |> Kernel.*(n - k + 1)
        |> div(k)
        |> do_combination(n, k - 1)
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fix/1 leaves valid and dropped cases untouched" do
    test "complex left operand `(expr) // n` is a no-op" do
      code = """
      defmodule Example do
        def gauss(n) do
          result = n * (n + 1) // 2
          result
        end
      end
      """

      assert fix(code) == code
    end

    test "valid div/2 call unchanged" do
      code = """
      defmodule Example do
        def half(n), do: div(n, 2)
      end
      """

      assert fix(code) == code
    end

    test "pipe into div unchanged" do
      code = """
      defmodule Example do
        def half(n), do: n |> div(2)
      end
      """

      assert fix(code) == code
    end

    test "comment with // unchanged" do
      code = """
      defmodule Example do
        # integer division // for Python users
        def half(n), do: div(n, 2)
      end
      """

      assert fix(code) == code
    end

    test "range step 0..-2//1 unchanged" do
      code = """
      middle = Enum.slice(list, 0..-2//1)

      """

      assert fix(code) == code
    end

    test "range step 1..10//2 unchanged" do
      code = """
      evens = Enum.to_list(1..10//2)

      """

      assert fix(code) == code
    end

    test "range step with variable bounds unchanged" do
      code = """
      Enum.reduce(n..m//-1, 0, fn i, acc -> i + acc end)

      """

      assert fix(code) == code
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # round-trip — fixed code no longer flags
  # ═══════════════════════════════════════════════════════════════════

  describe "round-trip" do
    test "fixed code produces zero analyze issues" do
      code = """
      def half(n), do: n // 2
      def step(acc, k), do: acc |> Kernel.//(k)
      """

      assert analyze(fix(code)) == []
    end
  end
end
