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

  defp fix(source, message \\ @message, line \\ 4) do
    FixTaskAsyncStreamCaseMatch.fix(source, %{
      severity: :warning,
      message: message,
      position: line
    })
  end

  test "replaces an all-dead case with the equivalent explicit failure" do
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
        case Task.async_stream(elements, fun, max_concurrency: 4) do
          unmatched_stream -> raise CaseClauseError, term: unmatched_stream
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not execute a multi-expression ok body" do
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
        case Task.async_stream(elements, fun) do
          unmatched_stream -> raise CaseClauseError, term: unmatched_stream
        end
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

  test "preserves failure when the case is used as an expression value" do
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
          case Task.async_stream(elements, fun) do
            unmatched_stream -> raise CaseClauseError, term: unmatched_stream
          end

        total + 1
      end
    end
    """

    confirm_fix(fix(input, @message, 5), expected)
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

  test "removes only the dead clause when a catch-all makes the case live" do
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

    expected = ~S"""
    defmodule Example do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          stream -> Enum.to_list(stream)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
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

  test "preserves failure when the diagnosed tuple clause destructures" do
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

    expected = ~S"""
    defmodule Example do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          unmatched_stream -> raise CaseClauseError, term: unmatched_stream
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "removes the diagnosed dead pair beside a differently shaped clause" do
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

    expected = ~S"""
    defmodule Example do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:error, reason, extra} -> {reason, extra}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "preserves the all-dead case failure instead of running the ok body" do
    input = ~S"""
    defmodule AsyncStreamCaseFailureRegression do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:ok, results} -> {:incorrectly_ran, results}
          {:error, reason} -> {:incorrectly_ran, reason}
        end
      end
    end
    """

    expected = ~S"""
    defmodule AsyncStreamCaseFailureRegression do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          unmatched_stream -> raise CaseClauseError, term: unmatched_stream
        end
      end
    end
    """

    fixed = fix(input, @message, 4)
    confirm_fix(fixed, expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(fixed)

    witness = ~S"""

    unless match?(
             {:error, %CaseClauseError{}},
             try do
               {:ok, AsyncStreamCaseFailureRegression.run([], fn value -> value end)}
             rescue
               error -> {:error, error}
             end
           ) do
      raise "case no longer fails with CaseClauseError"
    end
    """

    assert {:ok, _} = Credence.RuleHelpers.compile_and_capture(input <> witness)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(fixed <> witness)
  end

  test "uses the diagnostic line instead of rewriting an earlier quoted case" do
    input = ~S"""
    defmodule AsyncStreamCasePositionRegression do
      def quoted(elements, fun) do
        quote do
          case Task.async_stream(unquote(elements), unquote(fun)) do
            {:ok, results} -> results
            {:error, reason} -> reason
          end
        end
      end

      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:ok, results} -> Enum.to_list(results)
          {:error, reason} -> reason
        end
      end
    end
    """

    expected = ~S"""
    defmodule AsyncStreamCasePositionRegression do
      def quoted(elements, fun) do
        quote do
          case Task.async_stream(unquote(elements), unquote(fun)) do
            {:ok, results} -> results
            {:error, reason} -> reason
          end
        end
      end

      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          unmatched_stream -> raise CaseClauseError, term: unmatched_stream
        end
      end
    end
    """

    confirm_fix(fix(input, @message, 13), expected)
  end

  test "removes the diagnosed dead clause when the case has a live catch-all" do
    input = ~S"""
    defmodule AsyncStreamCaseCatchAllRegression do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:ok, results} -> {:incorrectly_ran, results}
          stream -> Enum.to_list(stream)
        end
      end
    end
    """

    expected = ~S"""
    defmodule AsyncStreamCaseCatchAllRegression do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          stream -> Enum.to_list(stream)
        end
      end
    end
    """

    fixed = fix(input, @message, 4)
    confirm_fix(fixed, expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(fixed)
  end

  test "matches and repairs the compiler diagnostic through the semantic pipeline" do
    input = ~S"""
    defmodule AsyncStreamCaseDispatchRegression do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          {:ok, results} -> results
          {:error, reason} -> {:error, reason}
        end
      end
    end
    """

    expected = ~S"""
    defmodule AsyncStreamCaseDispatchRegression do
      def run(elements, fun) do
        case Task.async_stream(elements, fun) do
          unmatched_stream -> raise CaseClauseError, term: unmatched_stream
        end
      end
    end
    """

    fixed =
      Credence.Semantic.fix(input,
        semantic_rules: [FixTaskAsyncStreamCaseMatch]
      )

    confirm_fix(fixed, expected)
  end
end
