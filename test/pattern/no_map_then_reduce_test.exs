defmodule Credence.Pattern.NoMapThenReduceTest do
  use ExUnit.Case

  alias Credence.Pattern.NoMapThenReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoMapThenReduce.check(ast, [])
  end

  describe "fires" do
    test "map result consumed only by reduce" do
      code = """
      defmodule M do
        def average_age(people) do
          ages = Enum.map(people, & &1["age"])
          {sum, count} = Enum.reduce(ages, {0, 0}, fn x, {s, c} -> {s + x, c + 1} end)
          sum / count
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_map_then_reduce
    end

    test "different map and reduce functions" do
      code = """
      defmodule M do
        def process(items) do
          values = Enum.map(items, fn x -> x * 2 end)
          Enum.reduce(values, 0, fn v, acc -> v + acc end)
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "two-argument reduce form" do
      code = """
      defmodule M do
        def process(items) do
          values = Enum.map(items, fn x -> x * 2 end)
          Enum.reduce(values, fn v, acc -> v + acc end)
        end
      end
      """

      assert length(check(code)) == 1
    end
  end

  describe "does not fire" do
    test "map result used in another statement besides reduce" do
      code = """
      defmodule M do
        def process(items) do
          values = Enum.map(items, fn x -> x * 2 end)
          IO.inspect(values)
          Enum.reduce(values, 0, fn v, acc -> v + acc end)
        end
      end
      """

      assert check(code) == []
    end

    test "map result rebound to non-map value before reduce" do
      code = """
      defmodule M do
        def process(items) do
          values = Enum.map(items, fn x -> x * 2 end)
          values = some_function(items)
          Enum.reduce(values, 0, fn v, acc -> v + acc end)
        end
      end
      """

      assert check(code) == []
    end

    test "no reduce consumer" do
      code = """
      defmodule M do
        def process(items) do
          values = Enum.map(items, fn x -> x * 2 end)
          Enum.sum(values)
        end
      end
      """

      assert check(code) == []
    end

    test "reduce on a different variable" do
      code = """
      defmodule M do
        def process(items, other) do
          values = Enum.map(items, fn x -> x * 2 end)
          Enum.reduce(other, 0, fn v, acc -> v + acc end)
        end
      end
      """

      assert check(code) == []
    end

    test "map result consumed by two reduces" do
      code = """
      defmodule M do
        def process(items) do
          values = Enum.map(items, fn x -> x * 2 end)
          a = Enum.reduce(values, 0, fn v, acc -> v + acc end)
          b = Enum.reduce(values, 1, fn v, acc -> v * acc end)
          {a, b}
        end
      end
      """

      assert check(code) == []
    end

    test "already idiomatic — no intermediate map" do
      code = """
      defmodule M do
        def average_age(people) do
          {sum, count} =
            Enum.reduce(people, {0, 0}, fn person, {s, c} ->
              {s + person["age"], c + 1}
            end)

          sum / count
        end
      end
      """

      assert check(code) == []
    end

    test "map result used as reduce accumulator, not enumerable" do
      code = """
      defmodule M do
        def process(items, list) do
          init = Enum.map(items, fn x -> x * 2 end)
          Enum.reduce(list, init, fn v, acc -> [v | acc] end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
