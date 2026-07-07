defmodule Credence.Semantic.NoRescueInExceptionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoRescueInException

  @message "struct Exception is undefined (there is such module but it does not define a struct)"

  defp fix(source, message, line \\ 1) do
    NoRescueInException.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "fixes rescue e in Exception to rescue e" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixes multiple rescue in Exception clauses" do
    input = """
    defmodule Multi do
      def run do
        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end

        try do
          raise "bang"
        rescue
          err in Exception ->
            {:error, err}
        end
      end
    end
    """

    expected = """
    defmodule Multi do
      def run do
        try do
          raise "boom"
        rescue
          e ->
            {:error, e}
        end

        try do
          raise "bang"
        rescue
          err ->
            {:error, err}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in Exception ->
            {:error, e}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no in Exception pattern" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "returns source unchanged when rescuing a different exception type" do
    input = """
    defmodule Example do
      def run do
        try do
          raise "boom"
        rescue
          e in ArgumentError ->
            {:error, e}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
