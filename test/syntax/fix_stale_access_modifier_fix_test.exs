defmodule Credence.Syntax.FixStaleAccessModifierFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixStaleAccessModifier
  defp analyze(code), do: FixStaleAccessModifier.analyze(code)
  defp fix(code), do: FixStaleAccessModifier.fix(code)

  # ── garbled prefixes ───────────────────────────────────────────

  describe "garbled prefixes" do
    test "pprivate defp → defp" do
      confirm_fix(
        fix("""
        pprivate defp calculate(x) do
          x * 2
        end
        """),
        """
        defp calculate(x) do
          x * 2
        end
        """
      )
    end

    test "pprivate defp one-liner" do
      confirm_fix(
        fix("pprivate defp get_sorted(nums), do: Enum.sort(nums)"),
        "defp get_sorted(nums), do: Enum.sort(nums)"
      )
    end
  end

  # ── redundant prefixes ────────────────────────────────────────

  describe "redundant prefixes" do
    test "private defp → defp" do
      confirm_fix(
        fix("""
        private defp calculate(x) do
          x * 2
        end
        """),
        """
        defp calculate(x) do
          x * 2
        end
        """
      )
    end

    test "public def → def" do
      confirm_fix(
        fix("""
        public def calculate(x) do
          x * 2
        end
        """),
        """
        def calculate(x) do
          x * 2
        end
        """
      )
    end
  end

  # ── contradictory prefixes ─────────────────────────────────────

  describe "contradictory prefixes (trusts Elixir keyword)" do
    test "private def → def" do
      confirm_fix(fix("private def calculate(x), do: x * 2"), "def calculate(x), do: x * 2")
    end

    test "public defp → defp" do
      confirm_fix(fix("public defp calculate(x), do: x * 2"), "defp calculate(x), do: x * 2")
    end
  end

  # ── other language modifiers ───────────────────────────────────

  describe "other language modifiers" do
    test "static def → def" do
      confirm_fix(fix("static def calculate(x), do: x * 2"), "def calculate(x), do: x * 2")
    end

    test "static defp → defp" do
      confirm_fix(fix("static defp calculate(x), do: x * 2"), "defp calculate(x), do: x * 2")
    end

    test "protected defp → defp" do
      confirm_fix(fix("protected defp calculate(x), do: x * 2"), "defp calculate(x), do: x * 2")
    end

    test "abstract def → def" do
      confirm_fix(fix("abstract def calculate(x), do: x * 2"), "def calculate(x), do: x * 2")
    end

    test "async def → def" do
      confirm_fix(fix("async def fetch(url), do: url"), "def fetch(url), do: url")
    end

    test "pub def → def" do
      confirm_fix(fix("pub def calculate(x), do: x * 2"), "def calculate(x), do: x * 2")
    end

    test "export def → def" do
      confirm_fix(fix("export def calculate(x), do: x * 2"), "def calculate(x), do: x * 2")
    end

    test "final def → def" do
      confirm_fix(fix("final def calculate(x), do: x * 2"), "def calculate(x), do: x * 2")
    end
  end

  # ── macro definitions ──────────────────────────────────────────

  describe "macro definitions" do
    test "private defmacro → defmacro" do
      confirm_fix(
        fix("""
        private defmacro my_macro(x) do
          x
        end
        """),
        """
        defmacro my_macro(x) do
          x
        end
        """
      )
    end

    test "private defmacrop → defmacrop" do
      confirm_fix(
        fix("""
        private defmacrop my_macro(x) do
          x
        end
        """),
        """
        defmacrop my_macro(x) do
          x
        end
        """
      )
    end
  end

  # ── preserves indentation ──────────────────────────────────────

  describe "preserves indentation" do
    test "two-space indent" do
      confirm_fix(
        fix("  pprivate defp calculate(x), do: x * 2"),
        "  defp calculate(x), do: x * 2"
      )
    end

    test "deep indent" do
      confirm_fix(
        fix("      private defp calculate(x), do: x * 2"),
        "      defp calculate(x), do: x * 2"
      )
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

      confirm_fix(fix(code), expected)
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

      confirm_fix(fix(code), expected)
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "correct defp unchanged" do
      code = "defp calculate(x), do: x * 2"

      confirm_fix(fix(code), code)
    end

    test "correct def unchanged" do
      code = "def calculate(x), do: x * 2"

      confirm_fix(fix(code), code)
    end

    test "private as variable unchanged" do
      code = "private = true"

      confirm_fix(fix(code), code)
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

  describe "fix output is well-formed" do
    test "fixed output parses" do
      assert valid_syntax?(
               fix("""
               pprivate defp calculate(x) do
                 x * 2
               end
               """)
             )
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # LITERALS — a modifier shown in an example is not a modifier
  #
  # All three of this rule's own "Examples" sit in its moduledoc heredoc
  # and all three were rewritten (docs/22 T3.10), deleting the very
  # prefixes the examples exist to demonstrate. Matching now runs against
  # a `Credence.SourceMask` shadow.
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/1 — only real code is rewritten" do
    test "leaves a modifier inside a moduledoc heredoc alone" do
      code = ~S'''
      defmodule Documented do
        @moduledoc """
        ## Examples

            private defp helper(x), do: x + 1
        """
      end
      '''

      confirm_fix(fix(code), code)
    end

    test "leaves a modifier inside a comment alone" do
      code = "# private defp helper(x), do: x + 1"

      confirm_fix(fix(code), code)
    end

    test "does not report a modifier that only appears in prose" do
      code = ~S'''
      @moduledoc """
          public def calculate(x), do: x * 2
      """
      '''

      assert analyze(code) == []
    end

    test "still fixes real code in a file that also documents the broken form" do
      code = ~S'''
      defmodule Both do
        @moduledoc """
      private defp documented(x), do: x
        """

        private defp real(x), do: x * 2
      end
      '''

      fixed = fix(code)

      assert fixed =~ "  defp real(x), do: x * 2"
      assert fixed =~ "private defp documented(x), do: x"
      assert valid_syntax?(fixed)
    end

    test "the rule does not rewrite its own source file" do
      source = File.read!("lib/syntax/fix_stale_access_modifier.ex")

      confirm_fix(fix(source), source)
    end
  end
end
