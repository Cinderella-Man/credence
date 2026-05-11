defmodule Credence.Pattern.NoIdentityFloatCoercionFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.NoIdentityFloatCoercion.fix(code, [])
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLY BY 1.0 — removal
  # ═══════════════════════════════════════════════════════════════════

  describe "fix * 1.0" do
    test "removes trailing * 1.0" do
      assert fix("n * 1.0") == "n"
    end

    test "removes leading 1.0 *" do
      assert fix("1.0 * n") == "n"
    end

    test "removes * 1.0 from complex expression" do
      assert fix("Enum.at(list, 0) * 1.0") == "Enum.at(list, 0)"
    end

    test "removes * 1.0 in arithmetic context" do
      assert fix("a + b * 1.0") == "a + b"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DIVIDE BY 1.0 — removal
  # ═══════════════════════════════════════════════════════════════════

  describe "fix / 1.0" do
    test "removes / 1.0" do
      assert fix("n / 1.0") == "n"
    end

    test "removes / 1.0 from complex expression" do
      assert fix("Enum.at(combined, mid_index) / 1.0") == "Enum.at(combined, mid_index)"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ADD 0.0 — removal
  # ═══════════════════════════════════════════════════════════════════

  describe "fix + 0.0" do
    test "removes trailing + 0.0" do
      assert fix("n + 0.0") == "n"
    end

    test "removes leading 0.0 +" do
      assert fix("0.0 + n") == "n"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SUBTRACT 0.0 — removal
  # ═══════════════════════════════════════════════════════════════════

  describe "fix - 0.0" do
    test "removes trailing - 0.0" do
      assert fix("n - 0.0") == "n"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SELF-ASSIGNMENT — line deletion
  # ═══════════════════════════════════════════════════════════════════

  describe "self-assignment deletion" do
    test "deletes var = var * 1.0" do
      input =
        "defmodule Example do\n  def run(count) do\n    count = count * 1.0\n    count\n  end\nend\n"

      expected =
        "defmodule Example do\n  def run(count) do\n    count\n  end\nend\n"

      assert fix(input) == expected
    end

    test "deletes var = 1.0 * var" do
      input =
        "defmodule Example do\n  def run(n) do\n    n = 1.0 * n\n    n\n  end\nend\n"

      expected =
        "defmodule Example do\n  def run(n) do\n    n\n  end\nend\n"

      assert fix(input) == expected
    end

    test "deletes var = var / 1.0" do
      input =
        "defmodule Example do\n  def run(n) do\n    n = n / 1.0\n    n\n  end\nend\n"

      expected =
        "defmodule Example do\n  def run(n) do\n    n\n  end\nend\n"

      assert fix(input) == expected
    end

    test "deletes var = var + 0.0" do
      input =
        "defmodule Example do\n  def run(n) do\n    n = n + 0.0\n    n\n  end\nend\n"

      expected =
        "defmodule Example do\n  def run(n) do\n    n\n  end\nend\n"

      assert fix(input) == expected
    end

    test "deletes var = var - 0.0" do
      input =
        "defmodule Example do\n  def run(n) do\n    n = n - 0.0\n    n\n  end\nend\n"

      expected =
        "defmodule Example do\n  def run(n) do\n    n\n  end\nend\n"

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SURROUNDING CODE — preservation
  # ═══════════════════════════════════════════════════════════════════

  describe "preserves surrounding code" do
    test "only touches the offending line" do
      input =
        "defmodule Example do\n  def foo(n), do: n + 1\n\n  def bar(n), do: n * 1.0\n\n  def baz(n), do: n - 1\nend\n"

      expected =
        "defmodule Example do\n  def foo(n), do: n + 1\n\n  def bar(n), do: n\n\n  def baz(n), do: n - 1\nend\n"

      assert fix(input) == expected
    end

    test "fixes multiple identity ops in one module" do
      input =
        "defmodule Example do\n  def foo(n), do: n * 1.0\n  def bar(n), do: n / 1.0\nend\n"

      expected =
        "defmodule Example do\n  def foo(n), do: n\n  def bar(n), do: n\nend\n"

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must not touch
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
