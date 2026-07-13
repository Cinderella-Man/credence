defmodule Credence.Syntax.FixStrayCommaBeforeWhenGuardAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixStrayCommaBeforeWhenGuard

  defp analyze(code), do: FixStrayCommaBeforeWhenGuard.analyze(code)

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — stray comma before `when` guard
  # ═══════════════════════════════════════════════════════════════════

  describe "flags stray comma before when guard" do
    test "comma and when on same line" do
      code = "def positive?(x), when x > 0, do: true"

      assert [%Issue{rule: :fix_stray_comma_before_when_guard}] = analyze(code)
    end

    test "comma on one line, when on next line" do
      code = """
      defmodule Example do
        def positive?(x),
          when x > 0, do: true
        def positive?(_), do: false
      end
      """

      assert [%Issue{rule: :fix_stray_comma_before_when_guard, meta: %{line: 2}}] = analyze(code)
    end

    test "reports correct line number" do
      code = """
      x = 1
      y = 2
      def foo(x),
        when x > 0, do: true
      """

      [issue] = analyze(code)
      assert issue.meta.line == 3
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — correct code
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag correct code" do
    test "function guard without stray comma" do
      code = "def positive?(x) when x > 0, do: true"

      assert analyze(code) == []
    end

    test "function without guard" do
      code = "def positive?(_), do: false"

      assert analyze(code) == []
    end

    test "case clause guard" do
      code = """
      case x do
        n when n > 0 -> :positive
        _ -> :zero
      end
      """

      assert analyze(code) == []
    end

    test "empty string" do
      assert analyze("") == []
    end

    test "defp with guard" do
      code = "defp valid?(x) when is_integer(x), do: true"

      assert analyze(code) == []
    end
  end
end
