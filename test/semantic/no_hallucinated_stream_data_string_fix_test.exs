defmodule Credence.Semantic.NoHallucinatedStreamDataStringFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedStreamDataString

  @alpha_message "function StreamData.alpha_string/0 is undefined or private"
  @range_message "function StreamData.string_of_length/2 is undefined or private"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedStreamDataString.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces StreamData.alpha_string() with StreamData.string(:alphanumeric)" do
    input = ~S"""
    defmodule HallucinatedStreamDataString do
      def gen_plain do
        StreamData.alpha_string()
      end
    end
    """

    expected = ~S"""
    defmodule HallucinatedStreamDataString do
      def gen_plain do
        StreamData.string(:alphanumeric)
      end
    end
    """

    confirm_fix(fix(input, @alpha_message, 3), expected)
  end

  test "replaces StreamData.string_of_length(min..max, type) with StreamData.string(type, min_length: min, max_length: max)" do
    input = ~S"""
    defmodule HallucinatedStreamDataString do
      def gen_ranged(min, max) do
        StreamData.string_of_length(min..max, :alphanumeric)
      end
    end
    """

    expected = ~S"""
    defmodule HallucinatedStreamDataString do
      def gen_ranged(min, max) do
        StreamData.string(:alphanumeric, min_length: min, max_length: max)
      end
    end
    """

    confirm_fix(fix(input, @range_message, 3), expected)
  end

  test "fixes both alpha_string and string_of_length in the same module" do
    input = ~S"""
    defmodule HallucinatedStreamDataString do
      def gen_plain do
        StreamData.alpha_string()
      end

      def gen_ranged(min, max) do
        StreamData.string_of_length(min..max, :alphanumeric)
      end
    end
    """

    expected = ~S"""
    defmodule HallucinatedStreamDataString do
      def gen_plain do
        StreamData.string(:alphanumeric)
      end

      def gen_ranged(min, max) do
        StreamData.string(:alphanumeric, min_length: min, max_length: max)
      end
    end
    """

    confirm_fix(fix(input, @alpha_message, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule HallucinatedStreamDataString do
      def gen_plain do
        StreamData.alpha_string()
      end

      def gen_ranged(min, max) do
        StreamData.string_of_length(min..max, :alphanumeric)
      end
    end
    """

    assert valid_syntax?(fix(input, @alpha_message, 3))
    assert valid_syntax?(fix(input, @range_message, 7))
  end

  test "returns source unchanged when no hallucinated calls present" do
    input = ~S"""
    defmodule CleanModule do
      def gen do
        StreamData.string(:alphanumeric)
      end
    end
    """

    confirm_fix(fix(input, @alpha_message, 3), input)
  end

  test "returns source unchanged for unrelated diagnostic message" do
    input = ~S"""
    defmodule SomeModule do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, "unrelated error"), input)
  end
end
