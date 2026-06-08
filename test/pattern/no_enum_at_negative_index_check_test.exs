defmodule Credence.Pattern.NoEnumAtNegativeIndexCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoEnumAtNegativeIndex

  describe "flags negative literal indices" do
    test "Enum.at(list, -1)" do
      code = """
      defmodule M do
        def f(list), do: Enum.at(list, -1)
      end
      """

      assert [%Issue{rule: :no_enum_at_negative_index}] = check(NoEnumAtNegativeIndex, code)
    end

    test "Enum.at(list, -2)" do
      code = """
      defmodule M do
        def f(list), do: Enum.at(list, -2)
      end
      """

      assert [%Issue{rule: :no_enum_at_negative_index}] = check(NoEnumAtNegativeIndex, code)
    end

    test "Enum.at(list, -3)" do
      code = """
      defmodule M do
        def f(list), do: Enum.at(list, -3)
      end
      """

      assert [%Issue{rule: :no_enum_at_negative_index}] = check(NoEnumAtNegativeIndex, code)
    end

    test "piped form" do
      code = """
      defmodule M do
        def f(list), do: list |> Enum.sort() |> Enum.at(-1)
      end
      """

      assert [%Issue{rule: :no_enum_at_negative_index}] = check(NoEnumAtNegativeIndex, code)
    end

    test "multiple on same list" do
      code =
        """
        defmodule M do
          def f(s) do
            a = Enum.at(s, -1)
            b = Enum.at(s, -2)
            {a, b}
          end
        end
        """

      assert length(check(NoEnumAtNegativeIndex, code)) == 2
    end

    test "inside if block" do
      code = """
      defmodule M do
        def f(list) do
          if true, do: Enum.at(list, -1)
        end
      end
      """

      assert length(check(NoEnumAtNegativeIndex, code)) == 1
    end

    test "in expression context (not assignment)" do
      code = """
      defmodule M do
        def f(s), do: Enum.at(s, -1) * Enum.at(s, -2)
      end
      """

      assert length(check(NoEnumAtNegativeIndex, code)) == 2
    end
  end

  describe "does NOT flag" do
    test "positive index" do
      assert check(NoEnumAtNegativeIndex, """
             defmodule M do
               def f(l), do: Enum.at(l, 0)
             end
             """) ==
               []
    end

    test "positive index 5" do
      assert check(NoEnumAtNegativeIndex, """
             defmodule M do
               def f(l), do: Enum.at(l, 5)
             end
             """) ==
               []
    end

    test "variable index" do
      assert check(NoEnumAtNegativeIndex, """
             defmodule M do
               def f(l, i), do: Enum.at(l, i)
             end
             """) ==
               []
    end

    test "expression index" do
      assert check(
               NoEnumAtNegativeIndex,
               """
               defmodule M do
                 def f(l, n), do: Enum.at(l, n - 1)
               end
               """
             ) == []
    end

    test "List.last" do
      assert check(NoEnumAtNegativeIndex, """
             defmodule M do
               def f(l), do: List.last(l)
             end
             """) ==
               []
    end

    test "unrelated Enum call" do
      assert check(NoEnumAtNegativeIndex, """
             defmodule M do
               def f(l), do: Enum.reverse(l)
             end
             """) ==
               []
    end
  end
end
