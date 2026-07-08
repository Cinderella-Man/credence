defmodule Credence.Syntax.NoIfElseInReceiveAfterFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoIfElseInReceiveAfter

  defp analyze(code), do: NoIfElseInReceiveAfter.analyze(code)
  defp fix(code), do: NoIfElseInReceiveAfter.fix(code)

  test "fixes receive with bare if/else after after" do
    input = """
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

    expected = """
    defmodule Example do
      def loop do
        receive do
          :msg -> :ok
        after
          0 ->
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

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    input = """
    defmodule Example do
      def loop do
        receive do
          :msg -> :ok
        after
          if true do
            :timeout
          else
            :done
          end
        end
      end
    end
    """

    assert analyze(fix(input)) == []
  end

  test "fixed output is well-formed (parses)" do
    input = """
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

    assert valid_syntax?(fix(input))
  end
end
