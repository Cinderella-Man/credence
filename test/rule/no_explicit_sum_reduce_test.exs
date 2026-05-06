defmodule Credence.Pattern.NoExplicitSumReduceTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoExplicitSumReduce.check(ast, [])
  end

  defp fix(code), do: Credence.Pattern.NoExplicitSumReduce.fix(code, [])

  describe "fixable?" do
    test "reports as fixable" do
      assert Credence.Pattern.NoExplicitSumReduce.fixable?() == true
    end
  end

  describe "NoExplicitSumReduce" do
    test "passes code that uses Enum.sum/1 instead of reduce" do
      code = """
      defmodule GoodSum do
        def sum_value(list) do
          Enum.sum(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses Enum.sum_by/2" do
      code = """
      defmodule GoodSumBy do
        def sum_by_value(list) do
          Enum.sum_by(list, & &1)
        end
      end
      """

      assert check(code) == []
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

      issues = check(code)

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

      issues = check(code)

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

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces sum reduce with Enum.sum/1" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> acc + x end)
      """

      result = fix(code)
      assert result =~ "Enum.sum(list)"
      refute result =~ "Enum.reduce"
    end

    test "handles reversed operand order" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> x + acc end)
      """

      result = fix(code)
      assert result =~ "Enum.sum(list)"
    end

    test "does not modify non-sum reductions" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> x * acc end)
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      refute result =~ "Enum.sum"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def total(list) do
          count = length(list)
          sum = Enum.reduce(list, 0, fn x, acc -> acc + x end)
          {count, sum}
        end
      end
      """

      result = fix(code)
      assert result =~ "length(list)"
      assert result =~ "Enum.sum(list)"
      assert result =~ "{count, sum}"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> x + acc end)
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Pattern.NoExplicitSumReduce.check(ast, []) == []
    end
  end
end
