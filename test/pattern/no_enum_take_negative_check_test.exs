defmodule Credence.Pattern.NoEnumTakeNegativeCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoEnumTakeNegative

  describe "NoEnumTakeNegative check" do
    test "detects Enum.take with negative literal" do
      code = """
      defmodule BadTake do
        def last_three(list) do
          sorted = Enum.sort(list)
          Enum.take(sorted, -3)
        end
      end
      """

      issues = check(NoEnumTakeNegative, code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_enum_take_negative
      assert issue.message =~ "-3"
    end

    test "detects piped Enum.take with negative literal" do
      code = """
      defmodule BadPiped do
        def last_three(list) do
          list |> Enum.sort() |> Enum.take(-3)
        end
      end
      """

      issues = check(NoEnumTakeNegative, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_take_negative
    end

    test "detects Enum.take(-1)" do
      code = """
      defmodule BadOne do
        def last(list), do: Enum.take(list, -1)
      end
      """

      issues = check(NoEnumTakeNegative, code)
      assert length(issues) == 1
      assert hd(issues).message =~ "-1"
    end

    test "recommends the semantics-preserving slice replacement" do
      [issue] = check(NoEnumTakeNegative, "Enum.take([2, 1, 3], -2)")

      assert issue.message ==
               "`Enum.take(list, -2)` forces a double traversal of the list to take from the end. " <>
                 "Use `Enum.slice(list, -2..-1//1)` instead."
    end

    test "passes Enum.take with positive count" do
      assert check(
               NoEnumTakeNegative,
               """
               defmodule G do
                 def f(l), do: Enum.sort(l, :desc) |> Enum.take(3)
               end
               """
             ) ==
               []
    end

    test "passes Enum.take with variable count" do
      assert check(NoEnumTakeNegative, """
             defmodule G do
               def f(l, n), do: Enum.take(l, n)
             end
             """) ==
               []
    end

    test "passes Enum.take with zero" do
      assert check(NoEnumTakeNegative, """
             defmodule G do
               def f(l), do: Enum.take(l, 0)
             end
             """) ==
               []
    end
  end
end
