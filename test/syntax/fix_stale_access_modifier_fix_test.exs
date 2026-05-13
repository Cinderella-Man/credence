defmodule Credence.Syntax.FixStaleAccessModifierFixTest do
  use ExUnit.Case

  defp analyze(code), do: Credence.Syntax.FixStaleAccessModifier.analyze(code)
  defp fix(code), do: Credence.Syntax.FixStaleAccessModifier.fix(code)

  # ── garbled prefixes ───────────────────────────────────────────

  describe "garbled prefixes" do
    test "pprivate defp → defp" do
      assert fix("pprivate defp calculate(x) do\n  x * 2\nend") ==
               "defp calculate(x) do\n  x * 2\nend"
    end

    test "pprivate defp one-liner" do
      assert fix("pprivate defp get_sorted(nums), do: Enum.sort(nums)") ==
               "defp get_sorted(nums), do: Enum.sort(nums)"
    end
  end

  # ── redundant prefixes ────────────────────────────────────────

  describe "redundant prefixes" do
    test "private defp → defp" do
      assert fix("private defp calculate(x) do\n  x * 2\nend") ==
               "defp calculate(x) do\n  x * 2\nend"
    end

    test "public def → def" do
      assert fix("public def calculate(x) do\n  x * 2\nend") ==
               "def calculate(x) do\n  x * 2\nend"
    end
  end

  # ── contradictory prefixes ─────────────────────────────────────

  describe "contradictory prefixes (trusts Elixir keyword)" do
    test "private def → def" do
      assert fix("private def calculate(x), do: x * 2") ==
               "def calculate(x), do: x * 2"
    end

    test "public defp → defp" do
      assert fix("public defp calculate(x), do: x * 2") ==
               "defp calculate(x), do: x * 2"
    end
  end

  # ── other language modifiers ───────────────────────────────────

  describe "other language modifiers" do
    test "static def → def" do
      assert fix("static def calculate(x), do: x * 2") ==
               "def calculate(x), do: x * 2"
    end

    test "static defp → defp" do
      assert fix("static defp calculate(x), do: x * 2") ==
               "defp calculate(x), do: x * 2"
    end

    test "protected defp → defp" do
      assert fix("protected defp calculate(x), do: x * 2") ==
               "defp calculate(x), do: x * 2"
    end

    test "abstract def → def" do
      assert fix("abstract def calculate(x), do: x * 2") ==
               "def calculate(x), do: x * 2"
    end

    test "async def → def" do
      assert fix("async def fetch(url), do: url") ==
               "def fetch(url), do: url"
    end

    test "pub def → def" do
      assert fix("pub def calculate(x), do: x * 2") ==
               "def calculate(x), do: x * 2"
    end

    test "export def → def" do
      assert fix("export def calculate(x), do: x * 2") ==
               "def calculate(x), do: x * 2"
    end

    test "final def → def" do
      assert fix("final def calculate(x), do: x * 2") ==
               "def calculate(x), do: x * 2"
    end
  end

  # ── macro definitions ──────────────────────────────────────────

  describe "macro definitions" do
    test "private defmacro → defmacro" do
      assert fix("private defmacro my_macro(x) do\n  x\nend") ==
               "defmacro my_macro(x) do\n  x\nend"
    end

    test "private defmacrop → defmacrop" do
      assert fix("private defmacrop my_macro(x) do\n  x\nend") ==
               "defmacrop my_macro(x) do\n  x\nend"
    end
  end

  # ── preserves indentation ──────────────────────────────────────

  describe "preserves indentation" do
    test "two-space indent" do
      assert fix("  pprivate defp calculate(x), do: x * 2") ==
               "  defp calculate(x), do: x * 2"
    end

    test "deep indent" do
      assert fix("      private defp calculate(x), do: x * 2") ==
               "      defp calculate(x), do: x * 2"
    end
  end

  # ── realistic context ──────────────────────────────────────────

  describe "realistic context" do
    test "the actual log case" do
      code = """
      defmodule MaximumProduct do
        def max_product(nums) when length(nums) < 2, do: raise "too short"
        def max_product(nums), do: calculate(Enum.sort(nums))

        pprivate defp calculate(sorted) do
          first_two = Enum.at(sorted, 0) * Enum.at(sorted, 1)
          last_two = Enum.at(sorted, -1) * Enum.at(sorted, -2)
          max(first_two, last_two)
        end

        pprivate defp get_sorted(nums), do: Enum.sort(nums)
      end
      """

      expected = """
      defmodule MaximumProduct do
        def max_product(nums) when length(nums) < 2, do: raise "too short"
        def max_product(nums), do: calculate(Enum.sort(nums))

        defp calculate(sorted) do
          first_two = Enum.at(sorted, 0) * Enum.at(sorted, 1)
          last_two = Enum.at(sorted, -1) * Enum.at(sorted, -2)
          max(first_two, last_two)
        end

        defp get_sorted(nums), do: Enum.sort(nums)
      end
      """

      assert fix(code) == expected
    end

    test "preserves surrounding code" do
      code = """
      defmodule Foo do
        def public_fn(x), do: x
        private defp helper(x), do: x + 1
        def another_public(y), do: y
      end
      """

      expected = """
      defmodule Foo do
        def public_fn(x), do: x
        defp helper(x), do: x + 1
        def another_public(y), do: y
      end
      """

      assert fix(code) == expected
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "correct defp unchanged" do
      code = "defp calculate(x), do: x * 2"
      assert fix(code) == code
    end

    test "correct def unchanged" do
      code = "def calculate(x), do: x * 2"
      assert fix(code) == code
    end

    test "private as variable unchanged" do
      code = "private = true"
      assert fix(code) == code
    end
  end

  # ── round-trip ─────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed code produces zero analyze issues" do
      code = """
      pprivate defp foo(x), do: x
      private defp bar(y), do: y
      public def baz(z), do: z
      """

      assert analyze(fix(code)) == []
    end
  end
end
