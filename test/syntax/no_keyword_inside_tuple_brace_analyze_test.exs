defmodule Credence.Syntax.NoKeywordInsideTupleBraceAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoKeywordInsideTupleBrace

  defp analyze(code), do: NoKeywordInsideTupleBrace.analyze(code)

  test "flags keyword syntax inside tuple braces" do
    input = ~S"""
    defmodule TupleKeywordTest do
      def build_step(name, compensation) do
        %{name: name, compensation: compensation, data: [{step_name: name, compensation: compensation}]}
      end
    end
    """

    assert [%Issue{rule: :no_keyword_inside_tuple_brace, meta: %{line: 3}}] = analyze(input)
  end

  test "flags standalone keyword braces in a list" do
    input = ~S"""
    defmodule TupleKeywordTest do
      def build_completed(name, compensation) do
        [{step_name: name, compensation: compensation}]
      end
    end
    """

    assert [%Issue{rule: :no_keyword_inside_tuple_brace, meta: %{line: 3}}] = analyze(input)
  end

  test "leaves valid map syntax alone" do
    input = ~S"""
    defmodule GoodCode do
      def build_map do
        %{step_name: "test", compensation: 42}
      end
    end
    """

    assert analyze(input) == []
  end

  test "leaves valid tuple syntax alone" do
    input = ~S"""
    defmodule GoodCode do
      def build_tuple do
        {:ok, "result"}
      end
    end
    """

    assert analyze(input) == []
  end

  test "leaves struct patterns with nested maps alone" do
    input = ~S"""
    defmodule PlugTest do
      def extract_user(%Plug.Conn{assigns: %{user_id: user_id}}) do
        user_id
      end
    end
    """

    assert analyze(input) == []
  end
end
