defmodule Credence.Semantic.NoDocOnPrivateFunctionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.NoDocOnPrivateFunction

  defp fix(source, line) do
    NoDocOnPrivateFunction.fix(source, %{
      severity: :warning,
      message: "defp helper/1 is private, @doc attribute is always discarded for private functions/macros/types",
      position: line
    })
  end

  test "removes @doc from private function with heredoc" do
    input = """
    defmodule Solution do
      @doc \"""
      Returns a greeting.
      \"""
      @spec greet(String.t()) :: String.t()
      def greet(name) do
        helper(name)
      end

      @doc \"""
      Builds the greeting string.
      \"""
      @spec helper(String.t()) :: String.t()
      defp helper(name), do: "Hello, " <> name
    end
    """

    expected = """
    defmodule Solution do
      @doc \"""
      Returns a greeting.
      \"""
      @spec greet(String.t()) :: String.t()
      def greet(name) do
        helper(name)
      end

      @spec helper(String.t()) :: String.t()
      defp helper(name), do: "Hello, " <> name
    end
    """

    assert fix(input, 14) == expected
  end

  test "removes @doc from private function with single-line doc" do
    input = """
    defmodule Solution do
      @doc "Builds the greeting string."
      @spec helper(String.t()) :: String.t()
      defp helper(name), do: "Hello, " <> name
    end
    """

    expected = """
    defmodule Solution do
      @spec helper(String.t()) :: String.t()
      defp helper(name), do: "Hello, " <> name
    end
    """

    assert fix(input, 4) == expected
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Solution do
      @doc \"""
      Builds the greeting string.
      \"""
      @spec helper(String.t()) :: String.t()
      defp helper(name), do: "Hello, " <> name
    end
    """

    assert valid_syntax?(fix(input, 6))
  end
end
