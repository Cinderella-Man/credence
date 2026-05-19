defmodule Credence.Pattern.NoEnumAtLoopAccessTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoEnumAtLoopAccess.check(ast, [])
  end

  describe "NoEnumAtLoopAccess" do
    test "flags Enum.at/2 inside a for loop" do
      code = """
      defmodule Example do
        def run(list) do
          for i <- 0..10 do
            Enum.at(list, i)
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_at_loop_access
    end

    test "flags Enum.at/2 inside Enum.map" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.map(0..10, fn i ->
            Enum.at(list, i)
          end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "does not flag literal index access" do
      code = """
      defmodule Example do
        def run(list) do
          Enum.at(list, 0)
          Enum.at(list, 1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.at outside loops" do
      code = """
      defmodule Example do
        def run(list, i) do
          Enum.at(list, i)
        end
      end
      """

      assert check(code) == []
    end

    test "flags nested loop usage" do
      code = """
      defmodule Example do
        def run(list) do
          for i <- 0..10 do
            for j <- 0..10 do
              Enum.at(list, j)
            end
          end
        end
      end
      """

      assert length(check(code)) >= 1
    end
  end
end
