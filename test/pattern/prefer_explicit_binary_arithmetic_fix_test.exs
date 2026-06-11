defmodule Credence.Pattern.PreferExplicitBinaryArithmeticFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferExplicitBinaryArithmetic

  test "rewrites pipe into rem to explicit call" do
    input = """
    String.length(input_string) |> rem(3)
    """

    expected = """
    rem(String.length(input_string), 3)
    """

    assert fix(PreferExplicitBinaryArithmetic, input) == expected
  end

  test "rewrites pipe into div to explicit call" do
    input = """
    numerator |> div(denominator)
    """

    expected = """
    div(numerator, denominator)
    """

    assert fix(PreferExplicitBinaryArithmetic, input) == expected
  end

  test "rewrites pipe into rem inside case" do
    input = """
    case String.length(input_string) |> rem(3) do
      0 -> :divisible
      _ -> :not_divisible
    end
    """

    expected = """
    case rem(String.length(input_string), 3) do
      0 -> :divisible
      _ -> :not_divisible
    end
    """

    assert fix(PreferExplicitBinaryArithmetic, input) == expected
  end

  test "fixes multiple occurrences" do
    input = """
    a = x |> rem(3)
    b = y |> div(7)
    {a, b}
    """

    expected = """
    a = rem(x, 3)
    b = div(y, 7)
    {a, b}
    """

    assert fix(PreferExplicitBinaryArithmetic, input) == expected
  end

  test "does not modify explicit rem call" do
    code = """
    rem(String.length(input_string), 3)
    """

    assert fix(PreferExplicitBinaryArithmetic, code) == code
  end

  test "does not modify explicit div call" do
    code = """
    div(numerator, denominator)
    """

    assert fix(PreferExplicitBinaryArithmetic, code) == code
  end

  test "does not modify pipe into non-arithmetic function" do
    code = """
    String.length(input_string) |> to_string()
    """

    assert fix(PreferExplicitBinaryArithmetic, code) == code
  end

  test "fix is idempotent" do
    input = """
    String.length(input_string) |> rem(3)
    """

    first_pass = fix(PreferExplicitBinaryArithmetic, input)
    second_pass = fix(PreferExplicitBinaryArithmetic, first_pass)
    assert first_pass == second_pass
  end

  test "fixed code passes check" do
    input = """
    String.length(input_string) |> rem(3)
    """

    assert check(PreferExplicitBinaryArithmetic, fix(PreferExplicitBinaryArithmetic, input)) == []
  end
end
