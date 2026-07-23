defmodule Credence.Semantic.FixTaskAsyncStreamCaseMatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixTaskAsyncStreamCaseMatch

  @message """
  the following clause will never match:

      {:ok, results} ->

  because it attempts to match on the result of:

      Task.async_stream(elements, fun, max_concurrency: 4)

  which has type:

      dynamic(({:cont or :halt or :suspend, term()}, term() -> term()))
  """

  defp fix(source, message \\ @message, line \\ 3) do
    FixTaskAsyncStreamCaseMatch.fix(source, %{
      severity: :warning,
      message: message,
      position: line
    })
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

    confirm_fix(fix(input), expected)
  end

  test "flattens a multi-expression ok body" do
    input = ~S"""
    defmodule FixAsyncStreamCase do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:ok, results} ->
            list = Enum.to_list(results)
            Enum.map(list, fn {:ok, val} -> val end)
          {:error, reason} ->
            {:error, reason}
        end
      end
    end
    """

    expected = ~S"""
    defmodule FixAsyncStreamCase do
      def run(elements, fun) do
        results = Task.async_stream(elements, fun)
        list = Enum.to_list(results)
        Enum.map(list, fn {:ok, val} -> val end)
      end
    end
    """

    confirm_fix(fix(input), expected)
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

    assert valid_syntax?(fix(input))
  end

  test "fixes a case used as an expression value" do
    input = ~S"""
    defmodule Example do
      def run(elements, fun) do
        total =
          case Task.async_stream(elements, fun) do
            {:ok, results} -> Enum.count(results)
            {:error, _reason} -> 0
          end

        total + 1
      end
    end
    """

    expected = ~S"""
    defmodule Example do
      def run(elements, fun) do
        total =
          (
            results = Task.async_stream(elements, fun)
            Enum.count(results)
          )

        total + 1
      end
    end
    """

    confirm_fix(fix(input), expected)
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

    confirm_fix(fix(input), input)
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

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when a catch-all clause makes the case live" do
    # The dead {:ok, results} clause still warns, but `stream ->` is the real
    # runtime path — rewriting would delete the code that actually runs.
    input = ~S"""
    defmodule Example do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:ok, results} -> Enum.map(results, fn {:ok, val} -> val end)
          stream -> Enum.to_list(stream)
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when a clause carries a guard" do
    input = ~S"""
    defmodule Example do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:ok, results} when is_list(results) -> results
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when the {:ok, _} clause destructures" do
    input = ~S"""
    defmodule Example do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:ok, [first | rest]} -> {first, rest}
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when a clause is a 3-tuple" do
    input = ~S"""
    defmodule Example do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:ok, results} -> results
          {:error, reason, extra} -> {reason, extra}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
