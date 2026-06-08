defmodule Credence.Pattern.NoExplicitSumReduceCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoExplicitSumReduce

  describe "NoExplicitSumReduce" do
    test "passes code that uses Enum.sum/1 instead of reduce" do
      code = """
      defmodule GoodSum do
        def sum_value(list) do
          Enum.sum(list)
        end
      end
      """

      assert check(NoExplicitSumReduce, code) == []
    end

    test "passes code that uses Enum.sum_by/2" do
      code = """
      defmodule GoodSumBy do
        def sum_by_value(list) do
          Enum.sum_by(list, & &1)
        end
      end
      """

      assert check(NoExplicitSumReduce, code) == []
    end

    test "detects if x + acc pattern inside reduce" do
      code = """
      defmodule BadPlus do
        def sum_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            x + acc
          end)
        end
      end
      """

      issues = check(NoExplicitSumReduce, code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_explicit_sum_reduce
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

      assert check(NoExplicitSumReduce, code) == []
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

      assert check(NoExplicitSumReduce, code) == []
    end

    test "detects multiple explicit Sum calls inside separate reduces" do
      code = """
      defmodule MultipleBadSum do
        def process(a, b) do
          x = Enum.reduce(a, 0, fn v, acc -> v + acc end)
          y = Enum.reduce(b, 0, fn v, acc -> v + acc end)
          {x, y}
        end
      end
      """

      issues = check(NoExplicitSumReduce, code)

      assert length(issues) == 2
    end

    test "ignores unrelated comparison operators outside reduce" do
      code = """
      defmodule NoReduce do
        def compare(a, b) do
          if a + b == 2 do
            a
          else
            b
          end
        end
      end
      """

      assert check(NoExplicitSumReduce, code) == []
    end
  end
end
