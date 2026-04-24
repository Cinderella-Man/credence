defmodule Credence.Rule.NoListAppendInLoopTest do
  use ExUnit.Case
  alias Credence.Issue

  describe "analyze/2 - NoListAppendInLoop Rule" do
    test "passes idiomatic code without issues" do
      code = """
      defmodule GoodCode do
        def process(list) do
          list
          |> Enum.reduce([], fn item, acc ->
            [item * 2 | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
    end

    test "detects ++ inside Enum.reduce" do
      code = """
      defmodule BadCodeReduce do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item * 2]
          end)
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert %Issue{} = issue
      assert issue.rule == :no_list_append_in_loop
      assert issue.severity == :high
      assert issue.message =~ "Avoid using '++' inside loops"
      assert issue.meta.line != nil
    end

    test "detects ++ inside a for comprehension" do
      code = """
      defmodule BadCodeFor do
        def process(list) do
          for item <- list do
            acc = []
            acc ++ [item]
          end
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert issue.rule == :no_list_append_in_loop
    end

    test "ignores ++ if it is outside of a looping construct" do
      code = """
      defmodule SafeAppend do
        def concat(list_a, list_b) do
          list_a ++ list_b
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == true
      assert result.issues == []
    end
  end

  describe "analyze/2 - Error Handling" do
    test "handles syntax errors gracefully by returning a critical issue" do
      # A true syntax error (missing closing bracket for the list)
      code = """
      defmodule BrokenCode do
        def process(list) do
          [1, 2, 3
        end
      end
      """

      result = Credence.analyze(code)

      assert result.valid == false
      assert length(result.issues) == 1

      issue = hd(result.issues)
      assert issue.rule == :parse_error
      assert issue.severity == :critical
      assert issue.message =~ "Syntax error"
    end
  end
end
