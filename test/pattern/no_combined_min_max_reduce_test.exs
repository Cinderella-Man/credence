defmodule Credence.Pattern.NoCombinedMinMaxReduceTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoCombinedMinMaxReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCombinedMinMaxReduce.check(ast, [])
  end

  describe "check/2" do
    test "detects combined min/max reduce with nil sentinel" do
      code = """
      defmodule BadMinMax do
        def min_max(list) do
          Enum.reduce(list, {nil, nil}, fn num, {min_acc, max_acc} ->
            min_val = if min_acc == nil or num < min_acc, do: num, else: min_acc
            max_val = if max_acc == nil or num > max_acc, do: num, else: max_acc
            {min_val, max_val}
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)

      assert %Issue{} = issue
      assert issue.rule == :no_combined_min_max_reduce
      assert issue.message =~ "min_max"
      assert issue.meta.line != nil
    end

    test "detects combined min/max reduce without nil guard" do
      code = """
      defmodule BadMinMaxNoGuard do
        def min_max([head | tail]) do
          Enum.reduce(tail, {head, head}, fn num, {min_acc, max_acc} ->
            min_val = if num < min_acc, do: num, else: min_acc
            max_val = if num > max_acc, do: num, else: max_acc
            {min_val, max_val}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT detect single min reduce" do
      code = """
      defmodule GoodMin do
        def find_min(list) do
          Enum.reduce(list, hd(list), fn x, acc ->
            if x < acc, do: x, else: acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect single max reduce" do
      code = """
      defmodule GoodMax do
        def find_max(list) do
          Enum.reduce(list, 0, fn x, acc ->
            max(x, acc)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect Enum.min_max/1 usage" do
      code = """
      defmodule GoodMinMax do
        def min_max(list) do
          Enum.min_max(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect tuple reduce that is not min/max" do
      code = """
      defmodule GoodTupleReduce do
        def sum_and_count(list) do
          Enum.reduce(list, {0, 0}, fn x, {sum, count} ->
            {sum + x, count + 1}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect reduce with map accumulator" do
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

    test "does NOT detect tuple reduce with only < comparison" do
      code = """
      defmodule GoodMinTuple do
        def process(list) do
          Enum.reduce(list, {nil, 0}, fn x, {min_acc, sum} ->
            min_val = if min_acc == nil or x < min_acc, do: x, else: min_acc
            {min_val, sum + x}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect tuple reduce with only > comparison" do
      code = """
      defmodule GoodMaxTuple do
        def process(list) do
          Enum.reduce(list, {nil, 0}, fn x, {max_acc, sum} ->
            max_val = if max_acc == nil or x > max_acc, do: x, else: max_acc
            {max_val, sum + x}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects combined min/max reduce using kernel max/min calls" do
      code = """
      defmodule BadMinMaxKernel do
        def min_max(list) do
          Enum.reduce(list, {hd(list), hd(list)}, fn num, {current_max, current_min} ->
            new_max = max(num, current_max)
            new_min = min(num, current_min)
            {new_max, new_min}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_combined_min_max_reduce
    end

    test "detects multiple combined min/max reduces" do
      code = """
      defmodule MultipleBad do
        def process(a, b) do
          x = Enum.reduce(a, {nil, nil}, fn v, {mn, mx} ->
            m1 = if v < mn, do: v, else: mn
            m2 = if v > mx, do: v, else: mx
            {m1, m2}
          end)

          y = Enum.reduce(b, {nil, nil}, fn v, {mn, mx} ->
            m1 = if v < mn, do: v, else: mn
            m2 = if v > mx, do: v, else: mx
            {m1, m2}
          end)

          {x, y}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "does NOT detect reduce with 3-tuple accumulator" do
      code = """
      defmodule GoodThreeTuple do
        def track(list) do
          Enum.reduce(list, {0, 0, 0}, fn x, {min, max, sum} ->
            {min(x, min), max(x, max), sum + x}
          end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
