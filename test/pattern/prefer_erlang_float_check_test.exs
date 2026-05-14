defmodule Credence.Pattern.PreferErlangFloatCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.PreferErlangFloat.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLY BY 1.0 — bare variable (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "var * 1.0" do
    test "flags n * 1.0" do
      assert flagged?("n * 1.0")
    end

    test "flags 1.0 * n" do
      assert flagged?("1.0 * n")
    end

    test "flags with longer variable name" do
      assert flagged?("my_value * 1.0")
    end

    test "flags underscore-prefixed variable" do
      assert flagged?("_n * 1.0")
    end

    test "flags self-assignment var = var * 1.0" do
      assert flagged?("count = count * 1.0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DIVIDE BY 1.0 — bare variable (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "var / 1.0" do
    test "flags n / 1.0" do
      assert flagged?("n / 1.0")
    end

    test "flags self-assignment n = n / 1.0" do
      assert flagged?("n = n / 1.0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ADD 0.0 — bare variable (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "var + 0.0" do
    test "flags n + 0.0" do
      assert flagged?("n + 0.0")
    end

    test "flags 0.0 + n" do
      assert flagged?("0.0 + n")
    end

    test "flags self-assignment n = n + 0.0" do
      assert flagged?("n = n + 0.0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SUBTRACT 0.0 — bare variable (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "var - 0.0" do
    test "flags n - 0.0" do
      assert flagged?("n - 0.0")
    end

    test "flags self-assignment n = n - 0.0" do
      assert flagged?("n = n - 0.0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REALISTIC CONTEXT (flagged)
  # ═══════════════════════════════════════════════════════════════════

  describe "realistic function contexts" do
    test "flags in one-liner def" do
      assert flagged?("def to_float(n), do: n * 1.0")
    end

    test "flags in defp with guard" do
      assert flagged?("defp to_float(n) when is_integer(n), do: n * 1.0")
    end

    test "flags bare var at end of multi-line body" do
      code = """
      def process(data) do
        result = calculate(data)
        result * 1.0
      end
      """

      assert flagged?(code)
    end

    test "flags in case branch" do
      code = """
      case type do
        :int -> n * 1.0
        :float -> n
      end
      """

      assert flagged?(code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "multiple hits" do
    test "flags two bare-var coercions in same module" do
      code = """
      defmodule Coerce do
        def to_float(n), do: n * 1.0
        def ensure_float(x), do: x + 0.0
      end
      """

      assert length(check(code)) == 2
    end

    test "flags mixed operators" do
      code = """
      defmodule Coerce do
        def mul(n), do: n * 1.0
        def div(n), do: n / 1.0
        def add(n), do: n + 0.0
      end
      """

      assert length(check(code)) == 3
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MUST NOT FLAG — non-bare operands (handled by NoIdentityFloatCoercion)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag non-bare operands" do
    test "function call * 1.0" do
      assert clean?("Enum.at(list, 0) * 1.0")
    end

    test "compound expression * 1.0" do
      assert clean?("(a + b) * 1.0")
    end

    test "1.0 * function call" do
      assert clean?("1.0 * Enum.sum(list)")
    end

    test "function call / 1.0" do
      assert clean?("Enum.count(list) / 1.0")
    end

    test "function call + 0.0" do
      assert clean?("Enum.sum(list) + 0.0")
    end

    test "tuple access * 1.0" do
      assert clean?("elem(pair, 0) * 1.0")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MUST NOT FLAG — real arithmetic
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag real arithmetic" do
    test "n * 2.0" do
      assert clean?("n * 2.0")
    end

    test "n * 1 (integer)" do
      assert clean?("n * 1")
    end

    test "n * 1.05" do
      assert clean?("n * 1.05")
    end

    test "n / 2.0" do
      assert clean?("n / 2.0")
    end

    test "n / 1 (integer)" do
      assert clean?("n / 1")
    end

    test "n + 1.0" do
      assert clean?("n + 1.0")
    end

    test "n - 1.0" do
      assert clean?("n - 1.0")
    end

    test "n + 0 (integer)" do
      assert clean?("n + 0")
    end

    test "n - 0 (integer)" do
      assert clean?("n - 0")
    end

    test "n * 1.0e5 (scientific notation)" do
      assert clean?("n * 1.0e5")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MUST NOT FLAG — negation
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag negation" do
    test "0.0 - n (negation, not identity)" do
      assert clean?("0.0 - n")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MUST NOT FLAG — already converted
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag already-correct code" do
    test ":erlang.float(n)" do
      assert clean?(":erlang.float(n)")
    end

    test "no coercion at all" do
      assert clean?("def run(n), do: n + 1")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # META
  # ═══════════════════════════════════════════════════════════════════

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.PreferErlangFloat.fixable?() == true
    end
  end
end
