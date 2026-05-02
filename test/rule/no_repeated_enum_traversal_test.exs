defmodule Credence.Rule.NoRepeatedEnumTraversalTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoRepeatedEnumTraversal.check(ast, [])
  end

  describe "NoRepeatedEnumTraversal" do
    test "passes when enumerable is traversed once" do
      code = """
      defmodule GoodCode do
        def count(list) do
          Enum.count(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes when multiple enumerables are traversed multiple times" do
      code = """
      defmodule GoodCode do
        def count(list) do
          Enum.count(list)
          Enum.sort([1, 2, 3])
          Enum.count([1, 2, 3, 4])
        end
      end
      """

      assert check(code) == []
    end

    test "detects repeated traversal of same enumerable" do
      code = """
      defmodule Stats do
        def stats(list) do
          max = Enum.max(list)
          min = Enum.min(list)
          count = Enum.count(list)

          {max, min, count}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 3

      Enum.each(issues, fn issue ->
        assert %Issue{} = issue
        assert issue.rule == :no_repeated_enum_traversal

        assert issue.message =~ "Repeated traversal"
        assert issue.message =~ "Enum"
        assert issue.meta.line != nil
      end)
    end

    test "detects repeated traversal inside conditionals" do
      code = """
      defmodule Conditional do
        def check(list) do
          if Enum.member?(list, 10) and Enum.member?(list, 20) do
            Enum.count(list)
          else
            0
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) == 3
    end

    test "does not flag different variables" do
      code = """
      defmodule DifferentLists do
        def compare(a, b) do
          {Enum.max(a), Enum.max(b)}
        end
      end
      """

      assert check(code) == []
    end

    test "detects repeated traversal with mixed Enum functions" do
      code = """
      defmodule Mixed do
        def process(list) do
          Enum.any?(list)
          Enum.find(list, &(&1 > 10))
          Enum.count(list)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 3
    end
  end
end
