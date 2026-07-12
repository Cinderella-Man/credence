defmodule Credence.Syntax.NoArrowOperatorOutsideComprehensionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoArrowOperatorOutsideComprehension

  defp analyze(code), do: NoArrowOperatorOutsideComprehension.analyze(code)
  defp fix(code), do: NoArrowOperatorOutsideComprehension.fix(code)

  test "fixes <- outside comprehension by replacing with =" do
    input = """
    defmodule M do
      def send_all(subscribers, msg) do
        Enum.each(subscribers, fn subscriber ->
          subscriber <- Process.whereis(subscriber) || subscriber
          send(subscriber, msg)
        end)
      end
    end
    """

    expected = """
    defmodule M do
      def send_all(subscribers, msg) do
        Enum.each(subscribers, fn subscriber ->
          subscriber = Process.whereis(subscriber) || subscriber
          send(subscriber, msg)
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule M do
      def send_all(subscribers, msg) do
        Enum.each(subscribers, fn subscriber ->
          subscriber <- Process.whereis(subscriber) || subscriber
          send(subscriber, msg)
        end)
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def send_all(subscribers, msg) do
        Enum.each(subscribers, fn subscriber ->
          subscriber <- Process.whereis(subscriber) || subscriber
          send(subscriber, msg)
        end)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "leaves <- inside for comprehension unchanged" do
    input = """
    defmodule M do
      def print_all(items) do
        for item <- items do
          IO.puts(item)
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves <- inside with block unchanged" do
    input = """
    defmodule M do
      def run do
        with {:ok, a} <- fetch(), {:ok, b} <- process(a) do
          {:ok, b}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
