defmodule Credence.Syntax.FixMapArrowInListBracketFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixMapArrowInListBracket

  defp analyze(code), do: FixMapArrowInListBracket.analyze(code)
  defp fix(code), do: FixMapArrowInListBracket.fix(code)

  test "fixes map arrow syntax inside list brackets" do
    input = """
    defmodule Saga do
      @spec new() :: [atom() => any()]
      def new, do: []
    end
    """

    expected = """
    defmodule Saga do
      @spec new() :: [{atom(), any()}]
      def new, do: []
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes standalone bracket arrow" do
    confirm_fix(fix(~S'[atom() => any()]'), ~S'[{atom(), any()}]')
  end

  test "fixed output no longer flags" do
    input = """
    defmodule Saga do
      @spec new() :: [atom() => any()]
      def new, do: []
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Saga do
      @spec new() :: [atom() => any()]
      def new, do: []
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "fix does not mangle valid keyword list" do
    input = ~S'[key: "val"]'
    confirm_fix(fix(input), input)
  end

  test "fix does not mangle valid map syntax" do
    input = ~S'%{atom() => any()}'
    confirm_fix(fix(input), input)
  end

  test "fix does not mangle valid tuple list" do
    input = ~S'[{atom(), any()}]'
    confirm_fix(fix(input), input)
  end

  test "fixes arrow inside braces without double-wrapping" do
    input = """
    defmodule Repro do
      def build(key, val) do
        [{key => val}]
      end
    end
    """

    expected = """
    defmodule Repro do
      def build(key, val) do
        [{key, val}]
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed arrow inside braces no longer flags" do
    input = """
    defmodule Repro do
      def build(key, val) do
        [{key => val}]
      end
    end
    """

    assert analyze(fix(input)) == []
  end
end
