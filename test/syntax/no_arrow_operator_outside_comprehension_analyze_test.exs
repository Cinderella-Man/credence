defmodule Credence.Syntax.NoArrowOperatorOutsideComprehensionAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoArrowOperatorOutsideComprehension

  defp analyze(code), do: NoArrowOperatorOutsideComprehension.analyze(code)

  test "flags <- used outside for/with" do
    code = """
    defmodule M do
      def send_all(subscribers, msg) do
        Enum.each(subscribers, fn subscriber ->
          subscriber <- Process.whereis(subscriber) || subscriber
          send(subscriber, msg)
        end)
      end
    end
    """

    assert [%Issue{rule: :no_arrow_operator_outside_comprehension}] = analyze(code)
  end

  test "leaves <- inside for comprehension alone" do
    code = """
    defmodule M do
      def print_all(items) do
        for item <- items do
          IO.puts(item)
        end
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves <- inside with block alone" do
    code = """
    defmodule M do
      def run do
        with {:ok, a} <- fetch(), {:ok, b} <- process(a) do
          {:ok, b}
        end
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves clean code alone" do
    code = """
    defmodule M do
      def greet(name) do
        greeting = "Hello, " <> name
        IO.puts(greeting)
      end
    end
    """

    assert analyze(code) == []
  end
end
