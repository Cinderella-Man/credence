defmodule Credence.Syntax.FixMapArrowInListBracketAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixMapArrowInListBracket

  defp analyze(code), do: FixMapArrowInListBracket.analyze(code)

  test "flags map arrow syntax inside list brackets" do
    input = ~S"""
    defmodule Saga do
      @spec new() :: [atom() => any()]
      def new, do: []
    end
    """

    assert [%Issue{rule: :fix_map_arrow_in_list_bracket, meta: %{line: 2}}] = analyze(input)
  end

  test "flags standalone bracket arrow" do
    assert [%Issue{rule: :fix_map_arrow_in_list_bracket}] = analyze(~S'[atom() => any()]')
  end

  test "leaves valid keyword list alone" do
    assert analyze(~S'[key: "val"]') == []
  end

  test "leaves valid map syntax alone" do
    assert analyze(~S'%{atom() => any()}') == []
  end

  test "leaves valid tuple list alone" do
    assert analyze(~S'[{atom(), any()}]') == []
  end
end
