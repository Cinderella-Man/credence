defmodule Credence.Rule.NoEnumTakeNegativeTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoEnumTakeNegative.check(ast, [])
  end

  describe "NoEnumTakeNegative" do
    test "passes Enum.take with positive count" do
      code = """
      defmodule Good do
        def top_three(list) do
          Enum.sort(list, :desc) |> Enum.take(3)
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.take with variable count" do
      code = """
      defmodule SafeVar do
        def take_n(list, n) do
          Enum.take(list, n)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.take with negative literal" do
      code = """
      defmodule BadTake do
        def last_three(list) do
          sorted = Enum.sort(list)
          Enum.take(sorted, -3)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_enum_take_negative

      assert issue.message =~ "-3"
      assert issue.meta.line != nil
    end

    test "detects piped Enum.take with negative literal" do
      code = """
      defmodule BadPiped do
        def last_three(list) do
          list |> Enum.sort() |> Enum.take(-3)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_take_negative
    end

    test "detects Enum.take(-1)" do
      code = """
      defmodule BadOne do
        def last(list), do: Enum.take(list, -1)
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).message =~ "-1"
    end
  end
end
