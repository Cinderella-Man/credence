defmodule Credence.Semantic.NoStreamDataTupleWithListFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoStreamDataTupleWithList

  @real_message "no function clause matching in StreamData.tuple/1"

  defp fix(source, message, line \\ 1) do
    NoStreamDataTupleWithList.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces StreamData.tuple([a, b]) with StreamData.tuple({a, b})" do
    input = """
    defmodule StreamDataTupleListArg do
      @moduledoc false

      def object do
        key_gen = StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
        value_gen = StreamData.integer()

        StreamData.list_of(
          StreamData.tuple([key_gen, value_gen]),
          max_length: 5
        )
        |> StreamData.map(&Map.new/1)
      end
    end
    """

    expected = """
    defmodule StreamDataTupleListArg do
      @moduledoc false

      def object do
        key_gen = StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
        value_gen = StreamData.integer()

        StreamData.list_of(
          StreamData.tuple({key_gen, value_gen}),
          max_length: 5
        )
        |> StreamData.map(&Map.new/1)
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule StreamDataTupleListArg do
      @moduledoc false

      def object do
        key_gen = StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
        value_gen = StreamData.integer()

        StreamData.list_of(
          StreamData.tuple([key_gen, value_gen]),
          max_length: 5
        )
        |> StreamData.map(&Map.new/1)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no StreamData.tuple with list" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged when tuple already has tuple arg" do
    input = """
    defmodule AlreadyTuple do
      def gen do
        StreamData.tuple({StreamData.integer(), StreamData.string(:alphanumeric)})
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
