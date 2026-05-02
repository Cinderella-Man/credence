defmodule Credence.Rule.NoListLastTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoListLast.check(ast, [])
  end

  describe "NoListLast" do
    test "passes code that avoids List.last" do
      code = """
      defmodule GoodCode do
        def median(list) do
          sorted = Enum.sort(list)
          mid = div(length(sorted), 2)
          Enum.at(sorted, mid)
        end
      end
      """

      assert check(code) == []
    end

    test "detects List.last/1" do
      code = """
      defmodule BadMedian do
        def median(list) do
          {left, _right} = Enum.split(list, div(length(list), 2))
          List.last(left)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_list_last

      assert issue.message =~ "List.last/1"
      assert issue.message =~ "O(n)"
      assert issue.meta.line != nil
    end

    test "detects multiple List.last calls" do
      code = """
      defmodule MultipleBad do
        def process(a, b) do
          {List.last(a), List.last(b)}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end

    test "ignores List.first (handled by different rule)" do
      code = """
      defmodule UsesFirst do
        def head(list) do
          List.first(list)
        end
      end
      """

      assert check(code) == []
    end
  end
end
