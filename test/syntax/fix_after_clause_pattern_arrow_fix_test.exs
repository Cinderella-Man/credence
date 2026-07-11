defmodule Credence.Syntax.FixAfterClausePatternArrowFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixAfterClausePatternArrow

  defp analyze(code), do: FixAfterClausePatternArrow.analyze(code)
  defp fix(code), do: FixAfterClausePatternArrow.fix(code)

  test "fixes after clause with pattern arrow" do
    input = """
    defmodule M do
      def run do
        try do
          {:ok, :value}
        after
          {result, new_state} ->
            IO.puts("after block")
            {result, new_state}
        end
      end
    end
    """

    expected = """
    defmodule M do
      def run do
        try do
          {:ok, :value}
        after
          IO.puts("after block")
          {result, new_state}
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule M do
      def run do
        try do
          {:ok, :value}
        after
          {result, new_state} ->
            IO.puts("after block")
            {result, new_state}
        end
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule M do
      def run do
        try do
          {:ok, :value}
        after
          {result, new_state} ->
            IO.puts("after block")
            {result, new_state}
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fixes after clause with simple variable pattern" do
    input = """
    defmodule M do
      def run do
        try do
          :ok
        after
          x ->
            cleanup()
        end
      end
    end
    """

    expected = """
    defmodule M do
      def run do
        try do
          :ok
        after
          cleanup()
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves valid after clause unchanged" do
    input = """
    defmodule M do
      def run do
        try do
          {:ok, :value}
        after
          IO.puts("after block")
          :ok
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end
end
