defmodule Credence.Semantic.NoHallucinatedMathRoundFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedMathRound

  @real_message "misplaced operator ::/2\n\nThe :: operator is typically used in bitstrings to specify types and sizes of segments:\n\n    <<size::32-integer, letter::utf8, rest::binary>>\n\nIt is also used in typespecs, such as @type and @spec, to describe inputs and outputs"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedMathRound.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces :math.round with round" do
    input = """
    defmodule HallucinatedMathRound do
      def compute(value) do
        k = :math.round(value / 2.0) |> max(1)
        k
      end
    end
    """

    expected = """
    defmodule HallucinatedMathRound do
      def compute(value) do
        k = round(value / 2.0) |> max(1)
        k
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "replaces :math.round in simple expression" do
    input = """
    defmodule Demo do
      def round_it(x) do
        :math.round(x)
      end
    end
    """

    expected = """
    defmodule Demo do
      def round_it(x) do
        round(x)
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Demo do
      def compute(value) do
        :math.round(value / 2.0)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no :math.round present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
