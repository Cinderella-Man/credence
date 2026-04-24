defmodule Credence.Rule.NoParamRebindingTest do
  use ExUnit.Case

  describe "analyze/2 - NoParamRebinding Rule" do
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

      result = Credence.analyze(code)

      rebind_issues = Enum.filter(result.issues, &(&1.rule == :no_param_rebinding))
      assert rebind_issues == []
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

      result = Credence.analyze(code)

      rebind_issues = Enum.filter(result.issues, &(&1.rule == :no_param_rebinding))
      assert length(rebind_issues) == 2

      messages = Enum.map(rebind_issues, & &1.message)
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

      result = Credence.analyze(code)

      rebind_issues = Enum.filter(result.issues, &(&1.rule == :no_param_rebinding))
      assert length(rebind_issues) >= 1

      issue = hd(rebind_issues)
      assert issue.message =~ "q"
      assert issue.severity == :info
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

      result = Credence.analyze(code)

      # `temp` is not a parameter, it's a local — rebinding it is still
      # arguably smelly but not what this rule targets
      rebind_issues = Enum.filter(result.issues, &(&1.rule == :no_param_rebinding))
      assert rebind_issues == []
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

      result = Credence.analyze(code)

      rebind_issues = Enum.filter(result.issues, &(&1.rule == :no_param_rebinding))
      assert rebind_issues == []
    end
  end
end
