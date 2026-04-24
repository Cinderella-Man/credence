defmodule Credence.Rule.NoListLastTest do
  use ExUnit.Case
  alias Credence.Issue

  describe "analyze/2 - NoListLast Rule" do
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

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
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

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert %Issue{} = issue
      assert issue.rule == :no_list_last
      assert issue.severity == :warning
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

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 2
    end

    test "ignores List.first (handled by different rule)" do
      code = """
      defmodule UsesFirst do
        def head(list) do
          List.first(list)
        end
      end
      """

      result = Credence.analyze(code)

      # NoListLast specifically targets List.last, not List.first
      list_last_issues = Enum.filter(result.issues, &(&1.rule == :no_list_last))
      assert list_last_issues == []
    end
  end
end
