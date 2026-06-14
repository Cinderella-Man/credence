defmodule Credence.Pattern.PreferBitshiftOverMathPowForPowerOf2CheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferBitshiftOverMathPowForPowerOf2

  test "flags trunc(:math.pow(2, x))" do
    assert flagged?(PreferBitshiftOverMathPowForPowerOf2, """
           trunc(:math.pow(2, x))
           """)
  end

  test "flags trunc(:math.pow(2, expr)) with complex expression" do
    assert flagged?(PreferBitshiftOverMathPowForPowerOf2, """
           trunc(:math.pow(2, n + 1))
           """)
  end

  test "leaves 1 <<< trunc(x) alone" do
    assert clean?(PreferBitshiftOverMathPowForPowerOf2, """
           1 <<< trunc(x)
           """)
  end

  test "leaves trunc(:math.pow(3, x)) alone" do
    assert clean?(PreferBitshiftOverMathPowForPowerOf2, """
           trunc(:math.pow(3, x))
           """)
  end

  test "leaves trunc(x) alone" do
    assert clean?(PreferBitshiftOverMathPowForPowerOf2, """
           trunc(x)
           """)
  end

  test "leaves :math.pow(2, x) without trunc alone" do
    assert clean?(PreferBitshiftOverMathPowForPowerOf2, """
           :math.pow(2, x)
           """)
  end
end
