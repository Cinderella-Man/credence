defmodule Credence.Semantic.NoHallucinatedQueueEmptyFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoHallucinatedQueueEmpty

  @real_message ":queue.empty/0 is undefined or private. Did you mean:\n\n    * is_empty/1\n"

  defp fix(source, message, line \\ 1) do
    NoHallucinatedQueueEmpty.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "replaces :queue.empty() with :queue.new()" do
    input = """
    defmodule QueueEmptyTest do
      def create do
        :queue.empty()
      end
    end
    """

    expected = """
    defmodule QueueEmptyTest do
      def create do
        :queue.new()
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule QueueEmptyTest do
      def create do
        :queue.empty()
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no :queue.empty() present" do
    input = """
    defmodule CleanExample do
      def create do
        :queue.new()
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
