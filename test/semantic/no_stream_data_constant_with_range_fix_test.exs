defmodule Credence.Semantic.NoStreamDataConstantWithRangeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoStreamDataConstantWithRange

  @real_message "incompatible types given to StreamData.integer/1:\n\n    StreamData.integer({min_length, max_length})\n\ngiven types:\n\n    -dynamic({term(), term()})-\n\nbut expected one of:\n\n    #1\n    dynamic(%Range{step: integer()})\n\n    #2\n    dynamic(%Range{})\n\nwhere \"max_length\" was given the type:\n\n    # type: dynamic()\n    # from: credence_check.ex:59:28\n    max_length\n\nwhere \"min_length\" was given the type:\n\n    # type: dynamic() or integer()\n    # from: credence_check.ex:61:16\n    min_length = max(0, min_length)\n"

  defp fix(source, message, line \\ 1) do
    NoStreamDataConstantWithRange.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces StreamData.constant with StreamData.member_of for range" do
    input = """
    defmodule ConstantWithRange do
      @spec chars() :: StreamData.t(char())
      def chars do
        StreamData.constant(?a..?z)
      end
    end
    """

    expected = """
    defmodule ConstantWithRange do
      @spec chars() :: StreamData.t(char())
      def chars do
        StreamData.member_of(?a..?z)
      end
    end
    """

    confirm_fix(fix(input, @real_message, 4), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ConstantWithRange do
      @spec chars() :: StreamData.t(char())
      def chars do
        StreamData.constant(?a..?z)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message, 4))
  end

  test "returns source unchanged when no StreamData.constant with range" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule Unrelated do
      def digits do
        StreamData.integer(0..9)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
