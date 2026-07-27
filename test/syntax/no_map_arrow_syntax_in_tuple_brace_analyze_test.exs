defmodule Credence.Syntax.NoMapArrowSyntaxInTupleBraceAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoMapArrowSyntaxInTupleBrace

  defp analyze(code), do: NoMapArrowSyntaxInTupleBrace.analyze(code)

  test "flags map arrow syntax inside tuple braces with string keys" do
    input = ~S"""
    defmodule Demo do
      def body do
        Jason.encode!({"error" => "File too large", "max_bytes" => 5_242_880})
      end
    end
    """

    assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace, meta: %{line: 3}}] = analyze(input)
  end

  test "flags standalone arrow braces" do
    assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace}] = analyze(~S'{"key" => "val"}')
  end

  test "flags atom key arrow syntax" do
    assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace}] = analyze(~S'{:key => "val"}')
  end

  test "flags variable key arrow syntax" do
    assert [%Issue{rule: :no_map_arrow_syntax_in_tuple_brace}] = analyze("{key => val}")
  end

  test "leaves valid map syntax alone" do
    input = ~S"""
    defmodule GoodCode do
      def build_map do
        %{"error" => "File too large", "max_bytes" => 5_242_880}
      end
    end
    """

    assert analyze(input) == []
  end

  test "leaves valid tuple syntax alone" do
    assert analyze(~S'{:ok, "result"}') == []
  end

  test "leaves valid tuple with numbers alone" do
    assert analyze("{1, 2, 3}") == []
  end

  test "leaves valid keyword map alone" do
    assert analyze(~S'%{key: "val"}') == []
  end
end
