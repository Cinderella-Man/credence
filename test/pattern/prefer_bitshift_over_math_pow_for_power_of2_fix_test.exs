defmodule Credence.Pattern.PreferBitshiftOverMathPowForPowerOf2FixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferBitshiftOverMathPowForPowerOf2

  test "rewrites trunc(:math.pow(2, x)) to 1 <<< trunc(x)" do
    input = """
    trunc(:math.pow(2, x))
    """

    expected = """
    1 <<< trunc(x)
    """

    assert fix(PreferBitshiftOverMathPowForPowerOf2, input) == expected
  end

  test "preserves surrounding code" do
    input = """
    defmodule M do
      def compute(n) do
        highest_bit_index = Kernel.floor(:math.log(n) / :math.log(2))
        trunc(:math.pow(2, highest_bit_index))
      end
    end
    """

    expected = """
    defmodule M do
      def compute(n) do
        highest_bit_index = Kernel.floor(:math.log(n) / :math.log(2))
        1 <<< trunc(highest_bit_index)
      end
    end
    """

    assert fix(PreferBitshiftOverMathPowForPowerOf2, input) == expected
  end

  test "does not modify non-matching code" do
    code = """
    trunc(:math.pow(3, x))
    """

    assert fix(PreferBitshiftOverMathPowForPowerOf2, code) == code
  end

  test "round-trip: fixed code produces no issues" do
    code = """
    trunc(:math.pow(2, x))
    """

    assert check(PreferBitshiftOverMathPowForPowerOf2, fix(PreferBitshiftOverMathPowForPowerOf2, code)) == []
  end
end
