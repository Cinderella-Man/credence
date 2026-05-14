defmodule Credence.Pattern.NoIdentityFloatCoercionCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoIdentityFloatCoercion.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLY BY 1.0 — non-bare operands (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "* 1.0 with non-bare operands" do
    test "flags function call * 1.0" do
      assert flagged?("Enum.at(list, div(length(list), 2)) * 1.0")
    end

    test "flags compound expression * 1.0" do
      assert flagged?("(a + b) * 1.0")
    end

    test "flags 1.0 * function call" do
      assert flagged?("1.0 * Enum.sum(list)")
    end

    test "flags literal * 1.0" do
      assert flagged?("(2 + 3) * 1.0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DIVIDE BY 1.0 — non-bare operands (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "/ 1.0 with non-bare operands" do
    test "flags function call / 1.0" do
      assert flagged?("Enum.at(combined, mid_index) / 1.0")
    end

    test "flags compound expression / 1.0" do
      assert flagged?("(a - b) / 1.0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ADD 0.0 — non-bare operands (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "+ 0.0 with non-bare operands" do
    test "flags function call + 0.0" do
      assert flagged?("Enum.sum(list) + 0.0")
    end

    test "flags 0.0 + function call" do
      assert flagged?("0.0 + Enum.sum(list)")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SUBTRACT 0.0 — non-bare operands (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "- 0.0 with non-bare operands" do
    test "flags function call - 0.0" do
      assert flagged?("Enum.count(list) - 0.0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "multiple hits" do
    test "flags two non-bare identity ops in same module" do
      code = """
      defmodule Example do
        def foo(list), do: Enum.sum(list) * 1.0
        def bar(list), do: Enum.count(list) / 1.0
      end
      """

      assert length(check(code)) == 2
    end

    test "flags mixed * 1.0 and + 0.0 on non-bare operands" do
      code = """
      defmodule Example do
        def foo(a, b), do: (a + b) * 1.0
        def bar(list), do: Enum.sum(list) + 0.0
      end
      """

      assert length(check(code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BARE-VARIABLE SKIP — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "skips bare-variable operands (handled by PreferErlangFloat)" do
    test "n * 1.0" do
      assert clean?("n * 1.0")
    end

    test "1.0 * n" do
      assert clean?("1.0 * n")
    end

    test "n / 1.0" do
      assert clean?("n / 1.0")
    end

    test "n + 0.0" do
      assert clean?("n + 0.0")
    end

    test "0.0 + n" do
      assert clean?("0.0 + n")
    end

    test "n - 0.0" do
      assert clean?("n - 0.0")
    end

    test "self-assignment count = count * 1.0" do
      assert clean?("count = count * 1.0")
    end

    test "self-assignment count = count / 1.0" do
      assert clean?("count = count / 1.0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE CASES — must NOT flag (real arithmetic)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag real arithmetic" do
    test "* 2.0" do
      assert clean?("n * 2.0")
    end

    test "* 1 (integer)" do
      assert clean?("n * 1")
    end

    test "* 1.05" do
      assert clean?("n * 1.05")
    end

    test "* 3.14" do
      assert clean?("n * 3.14")
    end

    test "/ 2.0" do
      assert clean?("n / 2.0")
    end

    test "/ 1 (integer — legitimate float coercion)" do
      assert clean?("n / 1")
    end

    test "+ 1.0" do
      assert clean?("n + 1.0")
    end

    test "- 1.0" do
      assert clean?("n - 1.0")
    end

    test "+ 0 (integer)" do
      assert clean?("n + 0")
    end

    test "- 0 (integer)" do
      assert clean?("n - 0")
    end

    test "0.0 - expr (negation, not identity)" do
      assert clean?("0.0 - n")
    end
  end

  describe "does not flag scientific notation" do
    test "* 1.0e5" do
      # Code.string_to_quoted evaluates 1.0e5 to 100_000.0, so not 1.0
      assert clean?("n * 1.0e5")
    end
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoIdentityFloatCoercion.fixable?() == true
    end
  end
end
