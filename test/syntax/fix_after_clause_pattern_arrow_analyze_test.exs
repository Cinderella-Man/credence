defmodule Credence.Syntax.FixAfterClausePatternArrowAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixAfterClausePatternArrow

  defp analyze(code), do: FixAfterClausePatternArrow.analyze(code)

  test "flags after clause with pattern arrow" do
    code = """
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

    assert [%Issue{rule: :fix_after_clause_pattern_arrow}] = analyze(code)
  end

  test "flags after clause with simple variable pattern arrow" do
    code = """
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

    assert [%Issue{rule: :fix_after_clause_pattern_arrow}] = analyze(code)
  end

  test "leaves valid after clause alone" do
    code = """
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

    assert analyze(code) == []
  end

  test "leaves code without try block alone" do
    code = """
    defmodule M do
      def run do
        IO.puts("hello")
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves case with -> alone" do
    code = """
    defmodule M do
      def run do
        case :ok do
          :ok -> :yes
          _ -> :no
        end
      end
    end
    """

    assert analyze(code) == []
  end
end
