defmodule Credence.Pattern.NoFilterThenMapTest do
  use ExUnit.Case

  alias Credence.Pattern.NoFilterThenMap

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoFilterThenMap.check(ast, [])
  end

  describe "NoFilterThenMap check" do
    test "detects Enum.filter |> Enum.map in pipeline" do
      code = """
      defmodule Bad do
        def prime_square_pairs(numbers) do
          numbers
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.filter(fn [first, second] -> prime?(first) and perfect_square?(second) end)
          |> Enum.map(fn [first, second] -> {first, second} end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_map
      assert issue.message =~ "Enum.filter"
      assert issue.message =~ "Enum.map"
      assert issue.message =~ "for"
    end

    test "detects Enum.filter |> Enum.map with simple predicate" do
      code = """
      defmodule Bad do
        def evens_squared(numbers) do
          numbers
          |> Enum.filter(fn x -> rem(x, 2) == 0 end)
          |> Enum.map(fn x -> x * x end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_map
    end

    test "detects with capture syntax" do
      code = """
      defmodule Bad do
        def positive_items(items) do
          items
          |> Enum.filter(&(&1 > 0))
          |> Enum.map(&(&1 * 2))
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_filter_then_map
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

    test "does not fire on Enum.map alone" do
      code = """
      defmodule Good do
        def double(numbers) do
          numbers
          |> Enum.map(fn x -> x * 2 end)
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

    test "does not fire on Enum.map |> Enum.filter" do
      code = """
      defmodule Good do
        def process(items) do
          items
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
