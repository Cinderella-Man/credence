defmodule Credence.Syntax.FixMismatchedClosingBraceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixMismatchedClosingBrace

  defp analyze(code), do: FixMismatchedClosingBrace.analyze(code)
  defp fix(code), do: FixMismatchedClosingBrace.fix(code)

  test "swaps mismatched } to ] in a simple list inside tuple" do
    input = ~S"""
    defmodule M do
      def f do
        {a, [b, c}, d}
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def f do
        {a, [b, c], d}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "swaps mismatched } to ] in the LLM reduce/tuple pattern" do
    input = ~S"""
    defmodule MismatchedBrace do
      def transform(data) do
        Enum.reduce(data, {[], [], %{}}, fn x, {ok, fail, stats} ->
          case x do
            :fail ->
              {ok, [%{reason: x} | stats[:failures] || []}, stats}
          end
        end)
      end
    end
    """

    expected = ~S"""
    defmodule MismatchedBrace do
      def transform(data) do
        Enum.reduce(data, {[], [], %{}}, fn x, {ok, fail, stats} ->
          case x do
            :fail ->
              {ok, [%{reason: x} | stats[:failures] || []], stats}
          end
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = ~S"""
    defmodule M do
      def f do
        {a, [b, c}, d}
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = ~S"""
    defmodule M do
      def f do
        {a, [b, c}, d}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fixes multiple mismatched braces iteratively" do
    input = ~S"""
    defmodule M do
      def f do
        x = [1, 2, 3}
        y = [4, 5, 6}
        {x, y}
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def f do
        x = [1, 2, 3]
        y = [4, 5, 6]
        {x, y}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes more than 50 mismatched braces" do
    input = Enum.map_join(1..51, "\n", fn i -> "x#{i} = {0, [#{i}}, 0}" end)
    expected = Enum.map_join(1..51, "\n", fn i -> "x#{i} = {0, [#{i}], 0}" end)

    fixed = fix(input)

    confirm_fix(fixed, expected)
    assert analyze(fixed) == []
    assert valid_syntax?(fixed)
  end

  test "does not choose between an intended list and tuple" do
    input = "def f, do: [1, 2}"

    confirm_fix(fix(input), input)
    assert analyze(input) == []
  end

  test "leaves valid code unchanged" do
    input = ~S"""
    defmodule M do
      def f do
        {a, [b, c], d}
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
