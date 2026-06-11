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
    end
    """

    assert fix(PreferNegateIfTrueFalse, input) == expected
  end
end
