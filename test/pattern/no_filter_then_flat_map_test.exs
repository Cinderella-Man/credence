defmodule Credence.Pattern.NoFilterThenFlatMapTest do
  use ExUnit.Case

  alias Credence.Pattern.NoFilterThenFlatMap

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoFilterThenFlatMap.check(ast, [])
  end

  describe "NoFilterThenFlatMap check" do
    test "detects Enum.filter |> Enum.flat_map in pipeline" do
      code = """
      defmodule Bad do
        def divisor_pairs(number) do
          limit = trunc(:math.sqrt(number))

          1..limit
          |> Enum.filter(fn i -> rem(number, i) == 0 end)
          |> Enum.flat_map(fn i ->
            d2 = div(number, i)
            if i == d2, do: [i], else: [i, d2]
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_flat_map
      assert issue.message =~ "Enum.filter"
      assert issue.message =~ "Enum.flat_map"
      assert issue.message =~ "intermediate list"
    end

    test "detects with simple predicate and transform" do
      code = """
      defmodule Bad do
        def evens_with_squares(numbers) do
          numbers
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
          |> Enum.flat_map(fn x -> [x, x * x] end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_flat_map
    end

    test "detects with capture syntax" do
      code = """
      defmodule Bad do
        def positive_pairs(items) do
          items
          |> Enum.filter(&(&1 > 0))
          |> Enum.flat_map(&([&1, &1 * 2]))
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_flat_map
    end

    test "does not fire on Enum.filter alone" do
      code = """
      defmodule Good do
        def evens(numbers) do
          numbers
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.flat_map alone" do
      code = """
      defmodule Good do
        def pairs(numbers) do
          numbers
          |> Enum.flat_map(fn x -> [x, x * x] end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.filter |> Enum.map" do
      code = """
      defmodule Good do
        def evens_squared(numbers) do
          numbers
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
          |> Enum.map(fn x -> x * x end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.filter |> Enum.into" do
      code = """
      defmodule Good do
        def to_set(items, pred) do
          items
          |> Enum.filter(pred)
          |> Enum.into(MapSet.new())
        end
      end
      """

      assert check(code) == []
    end

    test "does not fire on Enum.flat_map |> Enum.filter" do
      code = """
      defmodule Good do
        def process(items) do
          items
          |> Enum.flat_map(fn x -> [x, x + 1] end)
          |> Enum.filter(fn x -> x > 10 end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
