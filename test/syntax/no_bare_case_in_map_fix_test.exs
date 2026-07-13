defmodule Credence.Syntax.NoBareCaseInMapFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoBareCaseInMap

  defp analyze(code), do: NoBareCaseInMap.analyze(code)
  defp fix(code), do: NoBareCaseInMap.fix(code)

  test "wraps bare case in parentheses" do
    input = ~S"""
    %{
      val: case x do
        :a -> 1
      end
    }
    """

    expected = ~S"""
    %{
      val: (case x do
        :a -> 1
      end)
    }
    """

    confirm_fix(fix(input), expected)
  end

  test "wraps multiple bare cases in parentheses" do
    input = ~S"""
    %{
      a: case x do
        :y -> 1
      end,
      b: case y do
        :z -> 2
      end
    }
    """

    expected = ~S"""
    %{
      a: (case x do
        :y -> 1
      end),
      b: (case y do
        :z -> 2
      end)
    }
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes the spec example" do
    input = ~S"""
    defmodule M do
      def build(state) do
        %{
          max_duration: case state.max do
            {nil, nil} -> nil
            {p, d} -> {p, d}
          end,
          time_range: case {state.first, state.last} do
            {nil, nil} -> nil
            {f, l} -> {f, l}
          end,
          count: state.total
        }
      end
    end
    """

    expected = ~S"""
    defmodule M do
      def build(state) do
        %{
          max_duration: (case state.max do
            {nil, nil} -> nil
            {p, d} -> {p, d}
          end),
          time_range: (case {state.first, state.last} do
            {nil, nil} -> nil
            {f, l} -> {f, l}
          end),
          count: state.total
        }
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = ~S"""
    %{
      val: case x do
        :a -> 1
      end
    }
    """

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = ~S"""
    %{
      val: case x do
        :a -> 1
      end
    }
    """

    assert valid_syntax?(fix(code))
  end

  test "does not modify already-parenthesized case" do
    code = ~S"""
    %{
      val: (case x do
        :a -> 1
      end)
    }
    """

    confirm_fix(fix(code), code)
  end

  test "does not modify code without maps" do
    code = ~S"""
    case x do
      :a -> 1
    end
    """

    confirm_fix(fix(code), code)
  end
end
