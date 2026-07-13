defmodule Credence.Syntax.NoBareCaseInMapAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoBareCaseInMap

  defp analyze(code), do: NoBareCaseInMap.analyze(code)

  test "flags bare case in map value" do
    code = ~S"""
    %{
      val: case x do
        :a -> 1
      end
    }
    """

    assert [%Issue{rule: :no_bare_case_in_map, meta: %{line: 2}}] = analyze(code)
  end

  test "flags multiple bare cases in map" do
    code = ~S"""
    %{
      a: case x do
        :y -> 1
      end,
      b: case y do
        :z -> 2
      end
    }
    """

    issues = analyze(code)
    assert length(issues) == 2
    assert Enum.all?(issues, &(&1.rule == :no_bare_case_in_map))
  end

  test "leaves parenthesized case alone" do
    code = ~S"""
    %{
      val: (case x do
        :a -> 1
      end)
    }
    """

    assert analyze(code) == []
  end

  test "leaves non-case map values alone" do
    code = ~S"""
    %{
      a: 1,
      b: "hello",
      c: state.total
    }
    """

    assert analyze(code) == []
  end

  test "leaves code without maps alone" do
    code = ~S"""
    case x do
      :a -> 1
    end
    """

    assert analyze(code) == []
  end
end
