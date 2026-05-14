defmodule Credence.Pattern.NoIdentityFloatCoercionFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.NoIdentityFloatCoercion.fix(code, [])
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLY BY 1.0 — removal (non-bare operands)
  # ═══════════════════════════════════════════════════════════════════

  describe "fix * 1.0 with non-bare operands" do
    test "removes * 1.0 from function call" do
      assert fix("Enum.at(list, 0) * 1.0") == "Enum.at(list, 0)"
    end

    test "removes * 1.0 from compound expression" do
      assert fix("(a + b) * 1.0") == "(a + b)"
    end

    test "removes leading 1.0 * from function call" do
      assert fix("1.0 * Enum.sum(list)") == "Enum.sum(list)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DIVIDE BY 1.0 — removal (non-bare operands)
  # ═══════════════════════════════════════════════════════════════════

  describe "fix / 1.0 with non-bare operands" do
    test "removes / 1.0 from function call" do
      assert fix("Enum.at(combined, mid_index) / 1.0") == "Enum.at(combined, mid_index)"
    end

    test "removes / 1.0 from compound expression" do
      assert fix("(a - b) / 1.0") == "(a - b)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ADD 0.0 — removal (non-bare operands)
  # ═══════════════════════════════════════════════════════════════════

  describe "fix + 0.0 with non-bare operands" do
    test "removes trailing + 0.0 from function call" do
      assert fix("Enum.sum(list) + 0.0") == "Enum.sum(list)"
    end

    test "removes leading 0.0 + from function call" do
      assert fix("0.0 + Enum.sum(list)") == "Enum.sum(list)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SUBTRACT 0.0 — removal (non-bare operands)
  # ═══════════════════════════════════════════════════════════════════

  describe "fix - 0.0 with non-bare operands" do
    test "removes trailing - 0.0 from function call" do
      assert fix("Enum.count(list) - 0.0") == "Enum.count(list)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SELF-ASSIGNMENT — line deletion (non-bare operands)
  # ═══════════════════════════════════════════════════════════════════

  describe "self-assignment deletion with non-bare operands" do
    test "deletes result = Enum.sum(list) * 1.0 style line" do
      input = """
      defmodule Example do
        def run(list) do
          result = Enum.sum(list) * 1.0
          result
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          result = Enum.sum(list)
          result
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SURROUNDING CODE — preservation
  # ═══════════════════════════════════════════════════════════════════

  describe "preserves surrounding code" do
    test "only touches the offending line" do
      input = """
      defmodule Example do
        def foo(n), do: n + 1

        def bar(list), do: Enum.sum(list) * 1.0

        def baz(n), do: n - 1
      end
      """

      expected = """
      defmodule Example do
        def foo(n), do: n + 1

        def bar(list), do: Enum.sum(list)

        def baz(n), do: n - 1
      end
      """

      assert fix(input) == expected
    end

    test "fixes multiple non-bare identity ops in one module" do
      input = """
      defmodule Example do
        def foo(list), do: Enum.sum(list) * 1.0
        def bar(list), do: Enum.count(list) / 1.0
      end
      """

      expected = """
      defmodule Example do
        def foo(list), do: Enum.sum(list)
        def bar(list), do: Enum.count(list)
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BARE-VARIABLE SKIP — must NOT touch
  # ═══════════════════════════════════════════════════════════════════

  describe "skips bare-variable operands" do
    test "leaves n * 1.0 alone" do
      code = "n * 1.0"
      assert fix(code) == code
    end

    test "leaves 1.0 * n alone" do
      code = "1.0 * n"
      assert fix(code) == code
    end

    test "leaves n / 1.0 alone" do
      code = "n / 1.0"
      assert fix(code) == code
    end

    test "leaves n + 0.0 alone" do
      code = "n + 0.0"
      assert fix(code) == code
    end

    test "leaves 0.0 + n alone" do
      code = "0.0 + n"
      assert fix(code) == code
    end

    test "leaves n - 0.0 alone" do
      code = "n - 0.0"
      assert fix(code) == code
    end

    test "leaves self-assignment count = count * 1.0 alone" do
      code =
        "defmodule Example do\n  def run(count) do\n    count = count * 1.0\n    count\n  end\nend\n"

      assert fix(code) == code
    end

    test "leaves the PR author's to_float function alone" do
      code = """
      defmodule Coerce do
        defp to_float(n) when is_integer(n), do: n * 1.0
      end
      """

      assert fix(code) == code
    end

    test "leaves def body with bare var * 1.0 alone" do
      code = """
      defmodule Example do
        def foo(n), do: n * 1.0
        def bar(n), do: n / 1.0
      end
      """

      assert fix(code) == code
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must not touch (real arithmetic)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify clean code" do
    test "leaves * 2.0 alone" do
      code = "def run(n), do: n * 2.0"
      assert fix(code) == code
    end

    test "leaves * 1.05 alone" do
      code = "def run(n), do: n * 1.05"
      assert fix(code) == code
    end

    test "leaves / 1 (integer) alone" do
      code = "def run(n), do: n / 1"
      assert fix(code) == code
    end

    test "leaves / 2.0 alone" do
      code = "def run(n), do: n / 2.0"
      assert fix(code) == code
    end

    test "leaves 0.0 - expr alone (negation)" do
      code = "def run(n), do: 0.0 - n"
      assert fix(code) == code
    end

    test "leaves + 1.0 alone" do
      code = "def run(n), do: n + 1.0"
      assert fix(code) == code
    end

    test "returns source unchanged when nothing to fix" do
      code = "defmodule Example do\n  def run(n), do: n / 1\nend\n"
      assert fix(code) == code
    end

    test "leaves * 1.0e5 alone" do
      code = "defmodule Example do\n  def run(n), do: n * 1.0e5\nend\n"
      assert fix(code) == code
    end
  end
end
