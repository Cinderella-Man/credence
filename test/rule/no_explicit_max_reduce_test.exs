defmodule Credence.Rule.NoExplicitMaxReduceTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoExplicitMaxReduce.check(ast, [])
  end

  describe "NoExplicitMaxReduce" do
    test "passes code that uses Enum.max/1 instead of reduce" do
      code = """
      defmodule GoodMax do
        def max_value(list) do
          Enum.max(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses Enum.max_by/2" do
      code = """
      defmodule GoodMaxBy do
        def max_by_value(list) do
          Enum.max_by(list, & &1)
        end
      end
      """

      assert check(code) == []
    end

    test "detects explicit max/2 inside reduce" do
      code = """
      defmodule BadMaxReduce do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            max(x, acc)
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)

      assert %Issue{} = issue
      assert issue.rule == :no_explicit_max_reduce

      assert issue.message =~ "max-reduction"
      assert issue.meta.line != nil
    end

    test "detects if x > acc pattern inside reduce" do
      code = """
      defmodule BadIfGreater do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if x > acc do x else acc end
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_explicit_max_reduce
    end

    test "detects if x >= acc pattern inside reduce" do
      code = """
      defmodule BadIfGreaterEqual do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if x >= acc do x else acc end
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "does NOT detect sum reduction (must avoid false positives)" do
      code = """
      defmodule GoodSum do
        def sum(list) do
          Enum.reduce(list, 0, fn x, acc ->
            acc + x
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect map-based reductions" do
      code = """
      defmodule GoodMapReduce do
        def build_map(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, true)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect tuple-based state reducers" do
      code = """
      defmodule GoodStatefulReduce do
        def track(list) do
          Enum.reduce(list, {0, 0}, fn x, {a, b} ->
            {a + x, b}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects multiple explicit max calls inside separate reduces" do
      code = """
      defmodule MultipleBadMax do
        def process(a, b) do
          x = Enum.reduce(a, 0, fn v, acc -> max(v, acc) end)
          y = Enum.reduce(b, 0, fn v, acc -> max(v, acc) end)
          {x, y}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end

    test "ignores unrelated comparison operators outside reduce" do
      code = """
      defmodule NoReduce do
        def compare(a, b) do
          if a > b do
            a
          else
            b
          end
        end
      end
      """

      assert check(code) == []
    end
  end
end
