defmodule Credence.Pattern.PreferErlangFloatFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.PreferErlangFloat.fix(code, [])
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLY BY 1.0 → :erlang.float()
  # ═══════════════════════════════════════════════════════════════════

  describe "var * 1.0 → :erlang.float(var)" do
    test "trailing * 1.0" do
      assert fix("n * 1.0") == ":erlang.float(n)"
    end

    test "leading 1.0 *" do
      assert fix("1.0 * n") == ":erlang.float(n)"
    end

    test "longer variable name" do
      assert fix("my_value * 1.0") == ":erlang.float(my_value)"
    end

    test "underscore-prefixed variable" do
      assert fix("_n * 1.0") == ":erlang.float(_n)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DIVIDE BY 1.0 → :erlang.float()
  # ═══════════════════════════════════════════════════════════════════

  describe "var / 1.0 → :erlang.float(var)" do
    test "trailing / 1.0" do
      assert fix("n / 1.0") == ":erlang.float(n)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ADD 0.0 → :erlang.float()
  # ═══════════════════════════════════════════════════════════════════

  describe "var + 0.0 → :erlang.float(var)" do
    test "trailing + 0.0" do
      assert fix("n + 0.0") == ":erlang.float(n)"
    end

    test "leading 0.0 +" do
      assert fix("0.0 + n") == ":erlang.float(n)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SUBTRACT 0.0 → :erlang.float()
  # ═══════════════════════════════════════════════════════════════════

  describe "var - 0.0 → :erlang.float(var)" do
    test "trailing - 0.0" do
      assert fix("n - 0.0") == ":erlang.float(n)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SELF-ASSIGNMENT → :erlang.float()
  # ═══════════════════════════════════════════════════════════════════

  describe "self-assignment" do
    test "count = count * 1.0 → count = :erlang.float(count)" do
      input = """
      defmodule Example do
        def run(count) do
          count = count * 1.0
          count
        end
      end
      """

      expected = """
      defmodule Example do
        def run(count) do
          count = :erlang.float(count)
          count
        end
      end
      """

      assert fix(input) == expected
    end

    test "n = 1.0 * n → n = :erlang.float(n)" do
      input = """
      defmodule Example do
        def run(n) do
          n = 1.0 * n
          n
        end
      end
      """

      expected = """
      defmodule Example do
        def run(n) do
          n = :erlang.float(n)
          n
        end
      end
      """

      assert fix(input) == expected
    end

    test "n = n + 0.0 → n = :erlang.float(n)" do
      input = """
      defmodule Example do
        def run(n) do
          n = n + 0.0
          n
        end
      end
      """

      expected = """
      defmodule Example do
        def run(n) do
          n = :erlang.float(n)
          n
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REALISTIC FUNCTION CONTEXTS
  # ═══════════════════════════════════════════════════════════════════

  describe "realistic function contexts" do
    test "the PR author's to_float function" do
      input = """
      defmodule Coerce do
        defp to_float(n) when is_integer(n), do: n * 1.0
      end
      """

      expected = """
      defmodule Coerce do
        defp to_float(n) when is_integer(n), do: :erlang.float(n)
      end
      """

      assert fix(input) == expected
    end

    test "one-liner def" do
      input = """
      defmodule Coerce do
        def to_float(n), do: n * 1.0
      end
      """

      expected = """
      defmodule Coerce do
        def to_float(n), do: :erlang.float(n)
      end
      """

      assert fix(input) == expected
    end

    test "bare var at end of multi-line body" do
      input = """
      defmodule Example do
        def process(data) do
          result = calculate(data)
          result * 1.0
        end
      end
      """

      expected = """
      defmodule Example do
        def process(data) do
          result = calculate(data)
          :erlang.float(result)
        end
      end
      """

      assert fix(input) == expected
    end

    test "in case branch" do
      input = """
      defmodule Example do
        def coerce(n, type) do
          case type do
            :int -> n * 1.0
            :float -> n
          end
        end
      end
      """

      expected = """
      defmodule Example do
        def coerce(n, type) do
          case type do
            :int -> :erlang.float(n)
            :float -> n
          end
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "multiple coercions in same module" do
    test "fixes all bare-var coercions" do
      input = """
      defmodule Coerce do
        def mul(n), do: n * 1.0
        def div(n), do: n / 1.0
        def add(n), do: n + 0.0
      end
      """

      expected = """
      defmodule Coerce do
        def mul(n), do: :erlang.float(n)
        def div(n), do: :erlang.float(n)
        def add(n), do: :erlang.float(n)
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # PRESERVES SURROUNDING CODE
  # ═══════════════════════════════════════════════════════════════════

  describe "preserves surrounding code" do
    test "only touches offending lines" do
      input = """
      defmodule Example do
        def add(a, b), do: a + b
        def to_float(n), do: n * 1.0
        def sub(a, b), do: a - b
      end
      """

      expected = """
      defmodule Example do
        def add(a, b), do: a + b
        def to_float(n), do: :erlang.float(n)
        def sub(a, b), do: a - b
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MIXED BARE + NON-BARE ON SAME LINE
  # (PreferErlangFloat only rewrites bare-var sites; non-bare stays
  #  for NoIdentityFloatCoercion to handle in its own pass)
  # ═══════════════════════════════════════════════════════════════════

  describe "mixed bare and non-bare on same line" do
    test "rewrites bare var, leaves non-bare intact" do
      assert fix("{n * 1.0, Enum.sum(xs) * 1.0}") ==
               "{:erlang.float(n), Enum.sum(xs) * 1.0}"
    end

    test "rewrites both bare vars, leaves non-bare intact" do
      assert fix("{n * 1.0, Enum.sum(xs) * 1.0, m + 0.0}") ==
               "{:erlang.float(n), Enum.sum(xs) * 1.0, :erlang.float(m)}"
    end

    test "rewrites leading identity bare var, leaves non-bare intact" do
      assert fix("{1.0 * n, Enum.sum(xs) * 1.0}") ==
               "{:erlang.float(n), Enum.sum(xs) * 1.0}"
    end

    test "in function context" do
      input = """
      defmodule Example do
        def foo(n, xs), do: {n * 1.0, Enum.sum(xs) * 1.0}
      end
      """

      expected = """
      defmodule Example do
        def foo(n, xs), do: {:erlang.float(n), Enum.sum(xs) * 1.0}
      end
      """

      assert fix(input) == expected
    end

    test "division and addition mixed" do
      assert fix("{n / 1.0, Enum.count(xs) / 1.0}") ==
               "{:erlang.float(n), Enum.count(xs) / 1.0}"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — non-bare operands (handled by NoIdentityFloatCoercion)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch non-bare operands" do
    test "function call * 1.0 unchanged" do
      code = "Enum.at(list, 0) * 1.0"
      assert fix(code) == code
    end

    test "compound expression * 1.0 unchanged" do
      code = "(a + b) * 1.0"
      assert fix(code) == code
    end

    test "1.0 * function call unchanged" do
      code = "1.0 * Enum.sum(list)"
      assert fix(code) == code
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — real arithmetic
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch real arithmetic" do
    test "n * 2.0 unchanged" do
      code = "def run(n), do: n * 2.0"
      assert fix(code) == code
    end

    test "n * 1.05 unchanged" do
      code = "def run(n), do: n * 1.05"
      assert fix(code) == code
    end

    test "n * 1 (integer) unchanged" do
      code = "def run(n), do: n * 1"
      assert fix(code) == code
    end

    test "n / 2.0 unchanged" do
      code = "def run(n), do: n / 2.0"
      assert fix(code) == code
    end

    test "n + 1.0 unchanged" do
      code = "def run(n), do: n + 1.0"
      assert fix(code) == code
    end

    test "n - 1.0 unchanged" do
      code = "def run(n), do: n - 1.0"
      assert fix(code) == code
    end

    test "0.0 - n (negation) unchanged" do
      code = "def run(n), do: 0.0 - n"
      assert fix(code) == code
    end

    test "n * 1.0e5 unchanged" do
      code = "defmodule E do\n  def run(n), do: n * 1.0e5\nend\n"
      assert fix(code) == code
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NO-OPS — already correct
  # ═══════════════════════════════════════════════════════════════════

  describe "does not touch already-correct code" do
    test ":erlang.float(n) unchanged" do
      code = "def to_float(n), do: :erlang.float(n)"
      assert fix(code) == code
    end

    test "no coercion at all" do
      code = "defmodule E do\n  def run(n), do: n + 1\nend\n"
      assert fix(code) == code
    end
  end
end
