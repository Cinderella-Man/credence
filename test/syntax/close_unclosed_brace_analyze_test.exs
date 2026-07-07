defmodule Credence.Syntax.CloseUnclosedBraceAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.CloseUnclosedBrace

  defp analyze(code), do: CloseUnclosedBrace.analyze(code)

  test "flags code with unclosed tuple brace before end" do
    code = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 5}}] = analyze(code)
  end

  test "flags code with unclosed map brace before end" do
    code = """
    defmodule Example do
      def foo do
        %{key: "value"
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 3}}] = analyze(code)
  end

  test "leaves properly closed braces alone" do
    code = """
    defmodule Example do
      def init(_opts) do
        {:ok, %{key: "value"}}
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves code without braces alone" do
    code = """
    defmodule Example do
      def foo do
        IO.puts("hello")
      end
    end
    """

    assert analyze(code) == []
  end
end
