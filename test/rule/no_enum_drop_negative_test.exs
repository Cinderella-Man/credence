defmodule Credence.Rule.NoEnumDropNegativeTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoEnumDropNegative.check(ast, [])
  end

  describe "NoEnumDropNegative" do
    test "passes Enum.drop with positive count" do
      code = """
      defmodule Good do
        def skip_first(list), do: Enum.drop(list, 1)
      end
      """

      assert check(code) == []
    end

    test "passes Enum.drop with variable count" do
      code = """
      defmodule SafeVar do
        def drop_n(list, n), do: Enum.drop(list, n)
      end
      """

      assert check(code) == []
    end

    test "detects Enum.drop with negative literal" do
      code = """
      defmodule BadDrop do
        def remove_last(list) do
          Enum.drop(list, -1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_enum_drop_negative

      assert issue.message =~ "-1"
      assert issue.meta.line != nil
    end

    test "detects piped Enum.drop with negative literal" do
      code = """
      defmodule BadPiped do
        def remove_last(list) do
          list |> Enum.drop(-1)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_drop_negative
    end

    test "detects multiple negative drops" do
      code = """
      defmodule MultipleBad do
        def process(list) do
          a = Enum.drop(list, -1)
          b = Enum.drop(list, -2)
          {a, b}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end
  end
end
