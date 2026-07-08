defmodule Credence.Syntax.NoIfElseInReceiveAfterAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoIfElseInReceiveAfter

  defp analyze(code), do: NoIfElseInReceiveAfter.analyze(code)

  test "flags receive with bare if/else after after" do
    code = """
    defmodule Example do
      def loop do
        receive do
          :msg -> :ok
        after
          if true do
            Process.sleep(1)
            loop()
          else
            :done
          end
        end
      end
    end
    """

    assert [%Issue{rule: :no_if_else_in_receive_after}] = analyze(code)
  end

  test "flags receive with bare case after after" do
    code = """
    defmodule Example do
      def loop do
        receive do
          :msg -> :ok
        after
          case x do
            :a -> :b
            _ -> :c
          end
        end
      end
    end
    """

    assert [%Issue{rule: :no_if_else_in_receive_after}] = analyze(code)
  end

  test "flags receive with bare cond after after" do
    code = """
    defmodule Example do
      def loop do
        receive do
          :msg -> :ok
        after
          cond do
            true -> :ok
          end
        end
      end
    end
    """

    assert [%Issue{rule: :no_if_else_in_receive_after}] = analyze(code)
  end

  test "leaves valid receive/after alone" do
    code = """
    defmodule Example do
      def loop do
        receive do
          :msg -> :ok
        after
          5000 ->
            :timeout
        end
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves code without receive alone" do
    code = """
    defmodule Example do
      def greet(name), do: "Hello, " <> name
    end
    """

    assert analyze(code) == []
  end
end
