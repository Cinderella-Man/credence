defmodule Credence.Semantic.NoStreamDataIntegerTwoArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoStreamDataIntegerTwoArgs

  @real_message "function StreamData.__using__/1 is undefined or private"

  defp fix(source, message, line \\ 1) do
    NoStreamDataIntegerTwoArgs.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "replaces integer(min, max) with integer(min..max)" do
    input = """
    defmodule CommandGenerators do
      import StreamData

      def account_program do
        bind(integer(0, 10), fn n ->
          deposit_cmd = {:deposit, integer(1, 1000)}
          {:withdraw, integer(1, n)}
          constant(deposit_cmd)
        end)
      end
    end
    """

    expected = """
    defmodule CommandGenerators do
      import StreamData

      def account_program do
        bind(integer(0..10), fn n ->
          deposit_cmd = {:deposit, integer(1..1000)}
          {:withdraw, integer(1..n)}
          constant(deposit_cmd)
        end)
      end
    end
    """

    confirm_fix(fix(input, @real_message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule CommandGenerators do
      import StreamData

      def account_program do
        bind(integer(0, 10), fn n ->
          constant(n)
        end)
      end
    end
    """

    assert valid_syntax?(fix(input, @real_message))
  end

  test "returns source unchanged when no integer/2 calls" do
    input = """
    defmodule CleanExample do
      import StreamData

      def gen do
        integer(0..10)
      end
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule Unrelated do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @real_message), input)
  end
end
