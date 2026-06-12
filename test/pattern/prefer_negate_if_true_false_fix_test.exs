defmodule Credence.Pattern.PreferNegateIfTrueFalseFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferNegateIfTrueFalse

  test "rewrites the anti-pattern" do
    input = """
    if MapSet.member?(seen, current) do
      false
    else
      MapSet.put(seen, current)
      |> loop(sum_of_squared_digits(current))
    end
    """

    expected = """
    if !MapSet.member?(seen, current) do
      MapSet.put(seen, current)
      |> loop(sum_of_squared_digits(current))
    else
      false
    end
    """

    assert fix(PreferNegateIfTrueFalse, input) == expected
  end

  test "wraps binary condition in parens when negating" do
    input = """
    if len_a != len_b do
      false
    else
      do_work(a, b)
    end
    """

    expected = """
    if !(len_a != len_b) do
      do_work(a, b)
    else
      false
    end
    """

    assert fix(PreferNegateIfTrueFalse, input) == expected
  end

  # Regression (row 39705): a binary-op condition together with a MULTI-statement
  # else block previously dropped the closing paren of `!(cond)`, producing
  # `if !(rotated_digits == nil do ...` — a syntax error that had to be reverted.
  test "binary condition + multi-statement else block stays valid" do
    input = """
    if rotated_digits == nil do
      false
    else
      rotated_value = List.to_integer(rotated_digits)
      n != rotated_value
    end
    """

    expected = """
    if !(rotated_digits == nil) do
      rotated_value = List.to_integer(rotated_digits)
      n != rotated_value
    else
      false
    end
    """

    assert fix(PreferNegateIfTrueFalse, input) == expected
  end
end
