defmodule Credence.Semantic.FixUnderscoredPatternBindingForBodyUseFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixUnderscoredPatternBindingForBodyUse

  @message "undefined variable \"value\""

  defp fix(source, message, line) do
    FixUnderscoredPatternBindingForBodyUse.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "removes underscore from pattern binding in case clause" do
    input = """
    defmodule UnderscorePatternBindingBug do
      def handle(data) do
        case data do
          {key, _value} ->
            {key, value}
        end
      end
    end
    """

    expected = """
    defmodule UnderscorePatternBindingBug do
      def handle(data) do
        case data do
          {key, value} ->
            {key, value}
        end
      end
    end
    """

    confirm_fix(fix(input, @message, 5), expected)
  end

  test "removes underscore from pattern binding in function head" do
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
      def handle({:update, _value}), do
        value
      end
    end
    """

    expected = """
    defmodule M do
      def handle({:ok, _value}), do: :ok
      def handle({:error, _value}), do: :error
      def handle({:update, value}), do
        value
      end
    end
    """

    confirm_fix(fix(input, @message, 5), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule UnderscorePatternBindingBug do
      def handle(data) do
        case data do
          {key, _value} ->
            {key, value}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message, 5))
  end

  test "returns source unchanged when no underscore binding found" do
    input = """
    defmodule NoMatch do
      def test do
        x + 1
      end
    end
    """

    result = fix(input, @message, 3)
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
