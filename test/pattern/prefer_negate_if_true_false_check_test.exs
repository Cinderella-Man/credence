defmodule Credence.Pattern.PreferNegateIfTrueFalseCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferNegateIfTrueFalse

  test "flags the anti-pattern" do
    assert flagged?(PreferNegateIfTrueFalse, """
           if MapSet.member?(seen, current) do
             false
           else
             MapSet.put(seen, current)
             |> loop(sum_of_squared_digits(current))
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferNegateIfTrueFalse, """
           if !MapSet.member?(seen, current) do
             MapSet.put(seen, current)
             |> loop(sum_of_squared_digits(current))
           end
           """)
  end
end
