defmodule Credence.Semantic.AvoidBinaryMidPatternFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.AvoidBinaryMidPattern

  defp fix(source, message \\ nil, line \\ 1) do
    msg = message || "a binary field without size is only allowed at the end of a binary pattern"

    AvoidBinaryMidPattern.fix(source, %{
      severity: :error,
      message: msg,
      position: {line, 1}
    })
  end

  test "fixes the binary mid-pattern" do
    input = """
    defmodule Solution do
      def check(str) do
        <<first, rest::binary, last>> = str
        first == last
      end
    end
    """

    expected = """
    defmodule Solution do
      def check(str) do
        <<first, _rest::binary>> = str
        _last = binary_part(str, byte_size(str) - 1, 1)
        first == _last
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Solution do
      def check(str) do
        <<first, rest::binary, last>> = str
        first == last
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no binary mid-pattern" do
    input = """
    defmodule Solution do
      def check(str) do
        <<first, rest::binary>> = str
        first
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when binary is at the end" do
    input = """
    defmodule Solution do
      def check(str) do
        <<first, last, rest::binary>> = str
        first == last
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "handles different variable names" do
    input = """
    defmodule Parser do
      def parse(data) do
        <<head, middle::binary, tail>> = data
        head == tail
      end
    end
    """

    expected = """
    defmodule Parser do
      def parse(data) do
        <<head, _middle::binary>> = data
        _tail = binary_part(data, byte_size(data) - 1, 1)
        head == _tail
      end
    end
    """

    confirm_fix(fix(input), expected)
  end
end
