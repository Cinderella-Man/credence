defmodule Credence.Semantic.NoDocOnPrivateFunctionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoDocOnPrivateFunction

  defp fix(source, line) do
    NoDocOnPrivateFunction.fix(source, %{
      severity: :warning,
      message:
        "defp helper/1 is private, @doc attribute is always discarded for private functions/macros/types",
      position: line
    })
  end

  defp fix_count(source, line) do
    NoDocOnPrivateFunction.fix(source, %{
      severity: :warning,
      message:
        "defp count/2 is private, @doc attribute is always discarded for private functions/macros/types",
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

    confirm_fix(fix(input, 14), expected)
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

    confirm_fix(fix(input, 4), expected)
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

  # Regression: when position points to the @doc line itself (not the defp
  # line), the fix must still strip the @doc.  The Elixir compiler may emit
  # the diagnostic at the @doc attribute rather than the definition.
  test "removes @doc when position points to the @doc line (heredoc)" do
    input = """
    defmodule Solution do
      @doc \"""
      Counts items matching target in list.
      \"""
      @spec count(list(), integer()) :: non_neg_integer()
      defp count(list, target) do
        Enum.count(list, fn x -> x == target end)
      end

      def run(list, target), do: count(list, target)
    end
    """

    expected = """
    defmodule Solution do
      @spec count(list(), integer()) :: non_neg_integer()
      defp count(list, target) do
        Enum.count(list, fn x -> x == target end)
      end

      def run(list, target), do: count(list, target)
    end
    """

    # Position 2 = the @doc line, not the defp line (which is 7)
    assert fix_count(input, 2) == expected
  end

  test "removes @doc when position points to the @doc line (single-line)" do
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

    # Position 2 = the @doc line
    confirm_fix(fix(input, 2), expected)
  end

  # Safe-core boundary: a multi-line, non-heredoc @doc (string continuation)
  # is NOT stripped — removing just the first line would strand the
  # continuation (`@doc "a" <>` doesn't parse alone), so the fix leaves the
  # source untouched rather than emit broken / warning-swapped code.
  test "does not strip a multi-line non-heredoc @doc (continuation)" do
    input = """
    defmodule Solution do
      @doc "Builds the " <>
        "greeting string."
      defp helper(name), do: "Hello, " <> name
      def run(n), do: helper(n)
    end
    """

    # Position 2 = the @doc line.
    confirm_fix(fix(input, 2), input)
  end

  # @doc false is intentional — it should NOT be stripped.
  test "does not remove @doc false" do
    input = """
    defmodule Solution do
      @doc false
      defp helper(name), do: "Hello, " <> name
    end
    """

    confirm_fix(fix(input, 2), input)
    confirm_fix(fix(input, 3), input)
  end
end
