defmodule Credence.Semantic.FixHallucinatedStreamDataFlatMapFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedStreamDataFlatMap

  defp fix(source, message, line \\ 1) do
    FixHallucinatedStreamDataFlatMap.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  @message "function StreamData.flat_map/2 is undefined or private"

  test "fixes the source" do
    input = """
    defmodule FlatMapExample do
      def make do
        StreamData.flat_map(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    expected = """
    defmodule FlatMapExample do
      def make do
        StreamData.bind(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule FlatMapExample do
      def make do
        StreamData.flat_map(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end
end
