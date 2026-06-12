defmodule Credence.Pattern.AvoidDuplicateEnumAtFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidDuplicateEnumAt

  test "rewrites two Enum.at calls in if condition" do
    input = """
    if Enum.at(nums, mid) > Enum.at(nums, high) do
      :left
    else
      :right
    end
    """

    expected = """
    mid_elem = Enum.at(nums, mid)
    high_elem = Enum.at(nums, high)

    if mid_elem > high_elem do
      :left
    else
      :right
    end
    """

    assert fix(AvoidDuplicateEnumAt, input) == expected
  end

  test "rewrites with < comparison" do
    input = """
    if Enum.at(data, a) < Enum.at(data, b) do
      :less
    else
      :not_less
    end
    """

    expected = """
    a_elem = Enum.at(data, a)
    b_elem = Enum.at(data, b)

    if a_elem < b_elem do
      :less
    else
      :not_less
    end
    """

    assert fix(AvoidDuplicateEnumAt, input) == expected
  end

  test "no-op on code without the anti-pattern" do
    code = """
    if Enum.at(nums, mid) > 0 do
      :left
    else
      :right
    end
    """

    assert fix(AvoidDuplicateEnumAt, code) == code
  end

  test "fixed code produces zero issues (round-trip)" do
    code = """
    if Enum.at(nums, mid) > Enum.at(nums, high) do
      :left
    else
      :right
    end
    """

    assert check(AvoidDuplicateEnumAt, fix(AvoidDuplicateEnumAt, code)) == []
  end

  test "fixed code is valid Elixir" do
    code = """
    if Enum.at(nums, mid) > Enum.at(nums, high) do
      :left
    else
      :right
    end
    """

    assert valid_syntax?(fix(AvoidDuplicateEnumAt, code))
  end
end
