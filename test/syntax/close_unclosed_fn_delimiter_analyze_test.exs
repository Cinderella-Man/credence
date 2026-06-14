defmodule Credence.Syntax.CloseUnclosedFnDelimiterAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.CloseUnclosedFnDelimiter

  defp analyze(code), do: CloseUnclosedFnDelimiter.analyze(code)

  test "flags code where fn is missing its closing end before )" do
    code = """
    defmodule Solution do
      def replace_zero(matrix) do
        Enum.map(matrix, fn row ->
          non_zeros = Enum.filter(row, fn element -> element != 0 end)
          case non_zeros do
            [] -> row
            _ ->
              min_value = Enum.min(non_zeros)
              Enum.map(row, fn element ->
                if element == 0 do min_value else element end)
              end
          end
        end)
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 10}}] = analyze(code)
  end

  test "flags fn ... end)) with two unclosed fn levels" do
    code = """
    Enum.map(list, fn x ->
      Enum.map(list, fn y ->
        if y == 0 do x else y end))
    end
    """

    assert [%Issue{rule: :close_unclosed_fn_delimiter, meta: %{line: 3}}] = analyze(code)
  end

  test "leaves properly closed fn alone" do
    code = """
    Enum.map(list, fn x -> x end)
    """

    assert analyze(code) == []
  end

  test "leaves fn with inner block properly closed alone" do
    code = """
    Enum.map(list, fn x ->
      if x > 0 do x else 0 end
    end)
    """

    assert analyze(code) == []
  end

  test "leaves code without fn alone" do
    code = """
    if x > 0 do
      IO.puts("positive")
    end
    """

    assert analyze(code) == []
  end
end
