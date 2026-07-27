defmodule Credence.Semantic.NoUnderscoreInExpressionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnderscoreInExpression

  @message "invalid use of _. _ can only be used inside patterns to ignore values and cannot be used in expressions. Make sure you are inside a pattern or change it accordingly"

  defp fix(source, message \\ @message, line \\ 1) do
    NoUnderscoreInExpression.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  test "renames the underscore generator and its expression-position uses" do
    input = """
    defmodule Example do
      def build_map(n) do
        for _ <- 0..(n - 1), into: %{} do
          {_, :infinity}
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def build_map(n) do
        for idx <- 0..(n - 1), into: %{} do
          {idx, :infinity}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def build_map(n) do
        for _ <- 0..(n - 1), into: %{} do
          {_, :infinity}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "renames every expression-position underscore in a multi-statement body" do
    input = """
    defmodule M do
      def f(n) do
        for _ <- 0..(n - 1), into: %{} do
          IO.inspect(_)
          {_, :infinity}
        end
      end
    end
    """

    expected = """
    defmodule M do
      def f(n) do
        for idx <- 0..(n - 1), into: %{} do
          IO.inspect(idx)
          {idx, :infinity}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "picks a fresh name so it never shadows a variable the body references" do
    input = """
    defmodule M do
      def f(n, idx) do
        for _ <- 0..(n - 1), into: %{} do
          {_, idx}
        end
      end
    end
    """

    # `idx` is already referenced in the body (an outer parameter), so the
    # generator is renamed to `i` instead — the outer `idx` stays intact.
    expected = """
    defmodule M do
      def f(n, idx) do
        for i <- 0..(n - 1), into: %{} do
          {i, idx}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "returns source unchanged when there is no underscore in expression" do
    input = """
    defmodule Example do
      def build_map(n) do
        for i <- 0..(n - 1), into: %{} do
          {i, :infinity}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  # --- Deliberately NOT fixed: cases where a blind rename would change the
  # answer. The narrowed rule leaves these untouched (it only ever renames
  # `_` that sit unambiguously in expression position). ---

  test "no-op when the body contains a pattern match (renaming would alter match semantics)" do
    # `{_, _} = a` destructures any 2-tuple; rewriting to `{idx, idx} = a`
    # would instead require both elements equal -> MatchError on valid input.
    input = """
    defmodule M do
      def f(a, n) do
        for _ <- 0..(n - 1), into: %{} do
          {_, _} = a
          {_, :infinity}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the body contains a case with wildcard patterns" do
    input = """
    defmodule M do
      def f(a, n) do
        for _ <- 0..(n - 1), into: %{} do
          v =
            case a do
              {_, x} -> x
              _ -> 0
            end

          {_, v}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when a body binding would collide with the renamed generator" do
    input = """
    defmodule M do
      def f(n) do
        for _ <- 0..(n - 1), into: %{} do
          idx = compute()
          {_, idx}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when more than one generator is an underscore (ambiguous target)" do
    input = """
    defmodule M do
      def f(a, b) do
        for _ <- a, _ <- b, into: %{} do
          {_, :infinity}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the body contains an anonymous function" do
    input = """
    defmodule M do
      def f(n) do
        for _ <- 0..(n - 1), into: %{} do
          g = fn _ -> :infinity end
          {_, g.(1)}
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when it does not parse" do
    input = "defmodule M do def f("
    confirm_fix(fix(input), input)
  end

  # --- New: == with tuple containing underscore → match? ---

  test "converts == with tuple containing underscore to match?" do
    input = """
    defmodule UnderscoreInExpression do
      def count_busy(workers) do
        Enum.count(workers, fn {_, s} -> s == {:busy, _} end)
      end
    end
    """

    expected = """
    defmodule UnderscoreInExpression do
      def count_busy(workers) do
        Enum.count(workers, fn {_, s} -> match?({:busy, _}, s) end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "converts reversed == with tuple containing underscore to match?" do
    input = """
    defmodule M do
      def f(s) do
        {:busy, _} == s
      end
    end
    """

    expected = """
    defmodule M do
      def f(s) do
        match?({:busy, _}, s)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed == to match? output is well-formed (parses)" do
    input = """
    defmodule UnderscoreInExpression do
      def count_busy(workers) do
        Enum.count(workers, fn {_, s} -> s == {:busy, _} end)
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "no-op when both sides of == contain underscore" do
    input = """
    defmodule M do
      def f do
        {:busy, _} == {:idle, _}
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when == has no underscore in tuple" do
    input = """
    defmodule M do
      def f(s) do
        s == {:busy, :idle}
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
