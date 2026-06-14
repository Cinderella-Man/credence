defmodule Credence.Pattern.PreferExplicitBinaryArithmeticCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.PreferExplicitBinaryArithmetic

  describe "flags the anti-pattern" do
    test "pipe into rem" do
      assert flagged?(PreferExplicitBinaryArithmetic, "String.length(input_string) |> rem(3)")
    end

    test "pipe into div" do
      assert flagged?(PreferExplicitBinaryArithmetic, "numerator |> div(denominator)")
    end

    test "pipe into rem inside case" do
      assert flagged?(PreferExplicitBinaryArithmetic, """
             case String.length(input_string) |> rem(3) do
               0 -> :divisible
               _ -> :not_divisible
             end
             """)
    end

    test "returns correct rule name and message" do
      issues =
        check(PreferExplicitBinaryArithmetic, "String.length(s) |> rem(3)")

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :prefer_explicit_binary_arithmetic
      assert issue.message =~ "rem/2"
    end

    test "multiple occurrences" do
      issues =
        check(PreferExplicitBinaryArithmetic, """
        a = x |> rem(3)
        b = y |> div(7)
        {a, b}
        """)

      assert length(issues) == 2
    end
  end

  describe "leaves good code alone" do
    test "explicit rem call" do
      assert clean?(PreferExplicitBinaryArithmetic, "rem(String.length(input_string), 3)")
    end

    test "explicit div call" do
      assert clean?(PreferExplicitBinaryArithmetic, "div(numerator, denominator)")
    end

    test "pipe into non-arithmetic function" do
      assert clean?(PreferExplicitBinaryArithmetic, "String.length(input_string) |> to_string()")
    end

    test "rem used directly as function" do
      assert clean?(PreferExplicitBinaryArithmetic, "rem(a, b)")
    end
  end
end
