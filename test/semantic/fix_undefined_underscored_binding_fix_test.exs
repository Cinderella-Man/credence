defmodule Credence.Semantic.FixUndefinedUnderscoredBindingFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUndefinedUnderscoredBinding

  @message "undefined variable \"q_finish\""

  defp fix(source, message, line) do
    FixUndefinedUnderscoredBinding.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "removes underscore from tuple binding in function head" do
    input = """
    defmodule M do
      defp collect_overlapping(node, {q_start, _q_finish} = query, acc) do
        {start, finish} = node.interval
        if overlaps?(start, finish, q_start, q_finish) do
          [node.interval | acc]
        else
          acc
        end
      end

      defp overlaps?(s1, f1, s2, f2), do: s1 <= f2 and s2 <= f1
    end
    """

    expected = """
    defmodule M do
      defp collect_overlapping(node, {q_start, q_finish} = query, acc) do
        {start, finish} = node.interval
        if overlaps?(start, finish, q_start, q_finish) do
          [node.interval | acc]
        else
          acc
        end
      end

      defp overlaps?(s1, f1, s2, f2), do: s1 <= f2 and s2 <= f1
    end
    """

    confirm_fix(fix(input, @message, 4), expected)
  end

  test "removes underscore from simple parameter binding" do
    input = """
    defmodule M do
      def process(_data, text) do
        cleaned = String.trim(text)
        String.upcase(_data) <> cleaned
      end
    end
    """

    expected = """
    defmodule M do
      def process(data, text) do
        cleaned = String.trim(text)
        String.upcase(data) <> cleaned
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"data\"", 4), expected)
  end

  test "does not touch other function clauses" do
    input = """
    defmodule M do
      def handle({:ok, _value}), do: :ok
      def handle({:error, _value}), do: :error
      def handle({:update, _value}) do
        value
      end
    end
    """

    expected = """
    defmodule M do
      def handle({:ok, _value}), do: :ok
      def handle({:error, _value}), do: :error
      def handle({:update, value}) do
        value
      end
    end
    """

    confirm_fix(fix(input, "undefined variable \"value\"", 5), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      defp collect_overlapping(node, {q_start, _q_finish} = query, acc) do
        {start, finish} = node.interval
        if overlaps?(start, finish, q_start, q_finish) do
          [node.interval | acc]
        else
          acc
        end
      end

      defp overlaps?(s1, f1, s2, f2), do: s1 <= f2 and s2 <= f1
    end
    """

    assert valid_syntax?(fix(input, @message, 4))
  end

  test "returns source unchanged when no underscore binding found" do
    input = """
    defmodule NoMatch do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, "undefined variable \"x\"", 3)
    confirm_fix(result, input)
  end

  test "returns source unchanged for unrelated undefined variable" do
    input = """
    defmodule NoMatch do
      def test do
        IO.puts(y)
      end
    end
    """

    result = fix(input, "undefined variable \"y\"", 3)
    confirm_fix(result, input)
  end
end
