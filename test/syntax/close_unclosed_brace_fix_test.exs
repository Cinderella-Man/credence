defmodule Credence.Syntax.CloseUnclosedBraceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.CloseUnclosedBrace

  defp analyze(code), do: CloseUnclosedBrace.analyze(code)
  defp fix(code), do: CloseUnclosedBrace.fix(code)

  test "fixes unclosed tuple brace before end" do
    input = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    expected = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    assert valid_syntax?(fix(code))
  end

  test "does not modify already-valid code" do
    code = """
    defmodule Example do
      def init(_opts) do
        {:ok, %{key: "value"}}
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "fixes unclosed map brace before end" do
    input = """
    defmodule Example do
      def foo do
        %{key: "value"
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        %{key: "value"}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end
end
