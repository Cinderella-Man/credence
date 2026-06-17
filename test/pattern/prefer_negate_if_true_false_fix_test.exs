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

    confirm_fix(fix(PreferNegateIfTrueFalse, input), expected)
  end

  test "flips comparison operator instead of wrapping in !" do
    input = """
    if len_a != len_b do
      false
    else
      do_work(a, b)
    end
    """

    expected = """
    if len_a == len_b do
      do_work(a, b)
    else
      false
    end
    """

    confirm_fix(fix(PreferNegateIfTrueFalse, input), expected)
  end

  # Comparison operator is flipped directly — no wrapping in `!()`.
  test "binary condition + multi-statement else block — flips operator" do
    input = """
    if rotated_digits == nil do
      false
    else
      rotated_value = List.to_integer(rotated_digits)
      n != rotated_value
    end
    """

    expected = """
    if rotated_digits != nil do
      rotated_value = List.to_integer(rotated_digits)
      n != rotated_value
    else
      false
    end
    """

    confirm_fix(fix(PreferNegateIfTrueFalse, input), expected)
  end
end
