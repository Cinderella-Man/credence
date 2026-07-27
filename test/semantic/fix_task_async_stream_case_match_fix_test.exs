defmodule Credence.Semantic.FixTaskAsyncStreamCaseMatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixTaskAsyncStreamCaseMatch

  @message "the following clause will never match:\n\n    {:ok, results}\n\nbecause it attempts to match on the result of:\n\n    Task.async_stream(elements, fun, max_concurrency: 4)\n\nwhich has type:\n\n    dynamic((term(), term() -> term()))\n"

  defp fix(source, message, line \\ 1) do
    FixTaskAsyncStreamCaseMatch.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  test "removes case wrapper and binds stream directly" do
    input = ~S"""
    defmodule FixAsyncStreamCase do
      def run(elements, fun) do
        case Task.async_stream(elements, fun, max_concurrency: 4) do
          {:ok, results} ->
            Enum.map(results, fn {:ok, val} -> val end)
          {:error, reason} ->
            {:error, reason}
        end
      end
    end
    """

    expected = ~S"""
    defmodule FixAsyncStreamCase do
      def run(elements, fun) do
        results = Task.async_stream(elements, fun, max_concurrency: 4)
        Enum.map(results, fn {:ok, val} -> val end)
      end
    end
    """

    confirm_fix(fix(input, @message), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule FixAsyncStreamCase do
      def run(elements, fun) do
        case Task.async_stream(elements, fun, max_concurrency: 4) do
          {:ok, results} ->
            Enum.map(results, fn {:ok, val} -> val end)
          {:error, reason} ->
            {:error, reason}
        end
      end
    end
    """

    assert valid_syntax?(fix(input, @message))
  end

  test "returns source unchanged when no Task.async_stream case" do
    input = ~S"""
    defmodule Example do
      def run(elements, fun) do
        case SomeOtherModule.stream(elements, fun) do
          {:ok, results} -> results
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end

  test "returns source unchanged when case has no {:ok, _} clause" do
    input = ~S"""
    defmodule Example do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input, @message), input)
  end
end
