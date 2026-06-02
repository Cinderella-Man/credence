defmodule Credence.Pattern.NoReduceRangeWithElemTest do
  use ExUnit.Case

  alias Credence.Pattern.NoReduceRangeWithElem

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoReduceRangeWithElem.check(ast, [])
  end

  describe "flags reduce over range with elem on the range variable" do
    test "flags reduce over range with elem on two tuples" do
      code = """
      defmodule Bad do
        def addition_elements(tuple1, tuple2) do
          length1 = tuple_size(tuple1)
          length2 = tuple_size(tuple2)
          min_length = min(length1, length2)

          Enum.reduce(0..(min_length - 1), [], fn index, acc ->
            (elem(tuple1, index) + elem(tuple2, index))
            |> then(&[&1 | acc])
          end)
          |> Enum.reverse()
          |> List.to_tuple()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_reduce_range_with_elem
      assert hd(issues).message =~ "Enum.zip"
    end

    test "flags reduce over range with elem building a list" do
      code = """
      defmodule Bad do
        def collect(tuple) do
          Enum.reduce(0..(tuple_size(tuple) - 1), [], fn i, acc ->
            [elem(tuple, i) | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_reduce_range_with_elem
    end

    test "flags piped reduce over range with elem" do
      code = """
      defmodule Bad do
        def run(tup1, tup2) do
          0..3
          |> Enum.reduce([], fn i, acc ->
            [elem(tup1, i) + elem(tup2, i) | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_reduce_range_with_elem
    end
  end

  describe "does not fire on good code" do
    test "does not flag reduce over range without elem" do
      code = """
      defmodule Good do
        def run(list) do
          Enum.reduce(0..3, [], fn i, acc ->
            [i * 2 | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag reduce over list with elem" do
      code = """
      defmodule Good do
        def run(list) do
          Enum.reduce(list, 0, fn x, acc ->
            acc + x
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.zip + Enum.map" do
      code = """
      defmodule Good do
        def addition(tup1, tup2) do
          tup1
          |> Tuple.to_list()
          |> Enum.zip(Tuple.to_list(tup2))
          |> Enum.map(fn {a, b} -> a + b end)
          |> List.to_tuple()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map over tuple" do
      code = """
      defmodule Good do
        def double_tuple(tuple) do
          tuple
          |> Tuple.to_list()
          |> Enum.map(&(&1 * 2))
          |> List.to_tuple()
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag elem used outside reduce" do
      code = """
      defmodule Good do
        def first(tuple), do: elem(tuple, 0)
      end
      """

      assert check(code) == []
    end

    test "does not flag reduce with elem where index is not the range variable" do
      code = """
      defmodule Good do
        def run(tuples) do
          Enum.reduce(tuples, 0, fn tup, acc ->
            acc + elem(tup, 0)
          end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
