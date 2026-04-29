defmodule Credence.Rule.PreferEnumReverseTwoTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.PreferEnumReverseTwo.check(ast, [])
  end

  describe "PreferEnumReverseTwo" do
    test "detects Enum.reverse(acc) ++ tail" do
      code = """
      defmodule OptimizationTarget do
        def merge(acc, tail) do
          Enum.reverse(acc) ++ tail
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :prefer_enum_reverse_two
      assert issue.message =~ "Enum.reverse/2"
    end

    test "passes when using the optimized Enum.reverse/2" do
      code = """
      defmodule GoodCode do
        def merge(acc, tail), do: Enum.reverse(acc, tail)
      end
      """

      assert check(code) == []
    end

    test "ignores standard concatenation without reverse" do
      code = """
      defmodule StandardConcatenation do
        def combine(a, b), do: a ++ b
      end
      """

      assert check(code) == []
    end

    test "ignores Enum.reverse/1 when not used with ++" do
      code = """
      defmodule SimpleReverse do
        def flip(list), do: Enum.reverse(list)
      end
      """

      assert check(code) == []
    end
  end
end
