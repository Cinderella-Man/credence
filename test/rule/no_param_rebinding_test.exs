defmodule Credence.Rule.NoParamRebindingTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoParamRebinding.check(ast, [])
  end

  describe "NoParamRebinding" do
    test "passes code with no parameter rebinding" do
      code = """
      defmodule GoodReduce do
        def process(arr) do
          Enum.reduce(arr, {0, []}, fn x, {count, acc} ->
            new_count = count + 1
            new_acc = [x | acc]
            {new_count, new_acc}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects simple variable rebinding in fn body" do
      code = """
      defmodule BadRebind do
        def process(arr) do
          Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
            q = :queue.in(x, q)
            count = count + 1
            {count, q}
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2

      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "q"))
      assert Enum.any?(messages, &(&1 =~ "count"))
    end

    test "detects destructuring rebinding" do
      code = """
      defmodule BadDestructure do
        def process(queue) do
          Enum.reduce(1..5, queue, fn _x, q ->
            {{:value, _h}, q} = :queue.out(q)
            q
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      issue = hd(issues)
      assert issue.message =~ "q"

      assert issue.meta.line != nil
    end

    test "ignores rebinding of variables that are not parameters" do
      code = """
      defmodule SafeLocal do
        def process(list) do
          Enum.map(list, fn x ->
            temp = x * 2
            temp = temp + 1
            temp
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores underscore-prefixed parameters" do
      code = """
      defmodule SafeUnderscore do
        def process(list) do
          Enum.reduce(list, 0, fn _item, acc ->
            acc + 1
          end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
