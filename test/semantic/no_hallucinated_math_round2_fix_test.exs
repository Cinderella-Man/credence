defmodule Credence.Semantic.NoHallucinatedMathRound2FixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedMathRound2

  @round_message ":math.round/1 is undefined or private. Did you mean:\n\n    * ceil/1\n    * floor/1\n"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedMathRound2.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces :math.round with round in a simple assignment" do
    input = """
    defmodule Money do
      def convert(amount, rate) do
        converted = amount * rate
        rounded = :math.round(converted)
        rounded
      end
    end
    """

    expected = """
    defmodule Money do
      def convert(amount, rate) do
        converted = amount * rate
        rounded = round(converted)
        rounded
      end
    end
    """

    confirm_fix(fix(input, @round_message), expected)
  end

  test "replaces :math.round with round inside an if/else" do
    input = """
    defmodule Money do
      defstruct [:amount, :currency]

      def multiply(%Money{amount: amount, currency: currency}, factor) when is_number(factor) do
        result = amount * factor
        rounded = if result >= 0 do
          :math.round(result)
        else
          -(:math.round(-result))
        end
        new(rounded, currency)
      end
    end
    """

    expected = """
    defmodule Money do
      defstruct [:amount, :currency]

      def multiply(%Money{amount: amount, currency: currency}, factor) when is_number(factor) do
        result = amount * factor

        rounded =
          if result >= 0 do
            round(result)
          else
            -round(-result)
          end

        new(rounded, currency)
      end
    end
    """

    confirm_fix(fix(input, @round_message), expected)
  end

  test "replaces multiple :math.round calls in the same module" do
    input = """
    defmodule Money do
      defstruct [:amount, :currency]

      def multiply(%Money{amount: amount, currency: currency}, factor) when is_number(factor) do
        result = amount * factor
        rounded = if result >= 0 do
          :math.round(result)
        else
          -(:math.round(-result))
        end
        new(rounded, currency)
      end

      def convert(%Money{amount: amount, currency: currency}, to_currency, rates) do
        rate_from = Map.fetch!(rates, currency)
        rate_to = Map.fetch!(rates, to_currency)
        converted = amount * rate_from / rate_to
        rounded = :math.round(converted)
        new(rounded, to_currency)
      end

      defp new(amount, currency), do: %Money{amount: amount, currency: currency}
    end
    """

    expected = """
    defmodule Money do
      defstruct [:amount, :currency]

      def multiply(%Money{amount: amount, currency: currency}, factor) when is_number(factor) do
        result = amount * factor

        rounded =
          if result >= 0 do
            round(result)
          else
            -round(-result)
          end

        new(rounded, currency)
      end

      def convert(%Money{amount: amount, currency: currency}, to_currency, rates) do
        rate_from = Map.fetch!(rates, currency)
        rate_to = Map.fetch!(rates, to_currency)
        converted = amount * rate_from / rate_to
        rounded = round(converted)
        new(rounded, to_currency)
      end

      defp new(amount, currency), do: %Money{amount: amount, currency: currency}
    end
    """

    confirm_fix(fix(input, @round_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule X do
      def f(x), do: :math.round(x)
    end
    """

    assert valid_syntax?(fix(input, @round_message))
  end

  test "returns source unchanged when no :math.round present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @round_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input, @round_message), input)
  end
end
