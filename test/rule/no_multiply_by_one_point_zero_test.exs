defmodule Credence.Rule.NoMultiplyByOnePointZeroTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoMultiplyByOnePointZero.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoMultiplyByOnePointZero.fix(code, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Rule.NoMultiplyByOnePointZero.fixable?() == true
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK TESTS
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — positive cases" do
    test "flags expr * 1.0" do
      code = """
      defmodule Example do
        def run(n), do: n * 1.0
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_multiply_by_one_point_zero
      assert issue.message =~ "no effect"
    end

    test "flags complex expression * 1.0" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.at(list, div(length(list), 2)) * 1.0
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_multiply_by_one_point_zero
    end

    test "flags 1.0 * expr" do
      code = """
      defmodule Example do
        def run(n), do: 1.0 * n
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_multiply_by_one_point_zero
    end

    test "flags * 1.0 in larger expression" do
      code = """
      defmodule Example do
        def run(a, b), do: (a + b) * 1.0
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_multiply_by_one_point_zero
    end

    test "flags self-assignment var = var * 1.0" do
      code = """
      defmodule Example do
        def run(count) do
          count = count * 1.0
          count
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_multiply_by_one_point_zero
    end
  end

  describe "check/2 — negative cases" do
    test "does not flag * 2.0" do
      code = """
      defmodule Example do
        def run(n), do: n * 2.0
      end
      """

      assert check(code) == []
    end

    test "does not flag * 1 (integer)" do
      code = """
      defmodule Example do
        def run(n), do: n * 1
      end
      """

      assert check(code) == []
    end

    test "does not flag / 1" do
      code = """
      defmodule Example do
        def run(n), do: n / 1
      end
      """

      assert check(code) == []
    end

    test "does not flag normal float multiplication" do
      code = """
      defmodule Example do
        def run(n), do: n * 3.14
      end
      """

      assert check(code) == []
    end

    test "does not flag * 1.05" do
      code = """
      defmodule Example do
        def run(n), do: n * 1.05
      end
      """

      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — removes * 1.0" do
    test "removes * 1.0 from expression" do
      code = """
      defmodule Example do
        def run(n), do: n * 1.0
      end
      """

      fixed = fix(code)
      assert fixed =~ "def run(n), do: n"
      refute fixed =~ "1.0"
      refute fixed =~ "*"
    end

    test "removes * 1.0 from complex expression" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.at(list, 0) * 1.0
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.at(list, 0)"
      refute fixed =~ "* 1.0"
    end

    test "removes 1.0 * from expression" do
      code = """
      defmodule Example do
        def run(n), do: 1.0 * n
      end
      """

      fixed = fix(code)
      assert fixed =~ "def run(n), do: n"
      refute fixed =~ "1.0"
    end

    test "removes * 1.0 in arithmetic context" do
      code = """
      defmodule Example do
        def run(a, b), do: a + b * 1.0
      end
      """

      fixed = fix(code)
      assert fixed =~ "a + b"
      refute fixed =~ "1.0"
    end
  end

  describe "fix/2 — deletes self-assignment lines" do
    test "deletes var = var * 1.0" do
      code = """
      defmodule Example do
        def run(count) do
          count = count * 1.0
          count
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "count = count"
      refute fixed =~ "1.0"
      assert fixed =~ "count"
    end

    test "deletes var = 1.0 * var" do
      code = """
      defmodule Example do
        def run(n) do
          n = 1.0 * n
          n
        end
      end
      """

      fixed = fix(code)
      refute fixed =~ "n = 1.0"
      refute fixed =~ "n = n"
    end
  end

  describe "fix/2 — safety" do
    test "does not touch * 2.0" do
      code = """
      defmodule Example do
        def run(n), do: n * 2.0
      end
      """

      assert fix(code) == code
    end

    test "does not touch * 1.05" do
      code = """
      defmodule Example do
        def run(n), do: n * 1.05
      end
      """

      assert fix(code) == code
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def foo(n), do: n + 1

        def bar(n), do: n * 1.0

        def baz(n), do: n - 1
      end
      """

      fixed = fix(code)
      assert fixed =~ "def foo(n), do: n + 1"
      assert fixed =~ "def bar(n), do: n"
      assert fixed =~ "def baz(n), do: n - 1"
      refute fixed =~ "1.0"
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def run(n), do: n / 1
      end
      """

      assert fix(code) == code
    end

    test "does not match * 1.0e5 (scientific notation)" do
      code = """
      defmodule Example do
        def run(n), do: n * 1.0e5
      end
      """

      # 1.0e5 is 100000.0, not 1.0 — should not be flagged
      # Note: Code.string_to_quoted evaluates 1.0e5 to 100000.0, so check won't flag it
      assert fix(code) == code
    end
  end
end
