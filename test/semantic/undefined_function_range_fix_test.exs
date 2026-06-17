defmodule Credence.Semantic.UndefinedFunction.RangeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.Semantic.UndefinedFunction
  alias Range

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  defp msg(arity) do
    "undefined function range/#{arity} (expected MyModule to define such a function or for it to be imported, but none are available)"
  end

  describe "range/1 → 0..n - 1" do
    test "literal integer" do
      confirm_fix(
        fix(
          "range(10)",
          msg(1)
        ),
        "0..10 - 1"
      )
    end

    test "variable" do
      confirm_fix(
        fix(
          "range(n)",
          msg(1)
        ),
        "0..n - 1"
      )
    end

    test "function call as arg" do
      confirm_fix(
        fix(
          "range(length(list))",
          msg(1)
        ),
        "0..length(list) - 1"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "nums = range(10)",
          msg(1)
        ),
        "nums = 0..10 - 1"
      )
    end

    test "inside Enum.to_list" do
      confirm_fix(
        fix(
          "Enum.to_list(range(5))",
          msg(1)
        ),
        "Enum.to_list(0..5 - 1)"
      )
    end

    test "inside Enum.map" do
      confirm_fix(
        fix(
          "Enum.map(range(n), &to_string/1)",
          msg(1)
        ),
        "Enum.map(0..n - 1, &to_string/1)"
      )
    end
  end

  describe "range/2 → a..b - 1" do
    test "two literals" do
      confirm_fix(
        fix(
          "range(0, 10)",
          msg(2)
        ),
        "0..10 - 1"
      )
    end

    test "two variables" do
      confirm_fix(
        fix(
          "range(start, stop)",
          msg(2)
        ),
        "start..stop - 1"
      )
    end

    test "start at 1" do
      confirm_fix(
        fix(
          "range(1, n)",
          msg(2)
        ),
        "1..n - 1"
      )
    end

    test "function call as stop" do
      confirm_fix(
        fix(
          "range(0, length(list))",
          msg(2)
        ),
        "0..length(list) - 1"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "indices = range(0, n)",
          msg(2)
        ),
        "indices = 0..n - 1"
      )
    end

    test "inside Enum.each" do
      confirm_fix(
        fix(
          "Enum.each(range(1, 10), &IO.puts/1)",
          msg(2)
        ),
        "Enum.each(1..10 - 1, &IO.puts/1)"
      )
    end
  end

  describe "range/3 → a..b//c" do
    test "positive step" do
      confirm_fix(
        fix(
          "range(0, 10, 2)",
          msg(3)
        ),
        "0..10//2"
      )
    end

    test "negative step" do
      confirm_fix(
        fix(
          "range(10, 0, -1)",
          msg(3)
        ),
        "10..0//-1"
      )
    end

    test "negative step -2" do
      confirm_fix(
        fix(
          "range(10, 0, -2)",
          msg(3)
        ),
        "10..0//-2"
      )
    end

    test "all variables" do
      confirm_fix(
        fix(
          "range(a, b, step)",
          msg(3)
        ),
        "a..b//step"
      )
    end

    test "the actual LLM log case" do
      confirm_fix(
        fix(
          "range(max_num, min_num - 1, -1)",
          msg(3)
        ),
        "max_num..min_num - 1//-1"
      )
    end

    test "with nested function calls" do
      confirm_fix(
        fix(
          "range(length(a), length(b), 1)",
          msg(3)
        ),
        "length(a)..length(b)//1"
      )
    end

    test "arithmetic in start" do
      confirm_fix(
        fix(
          "range(n - 1, 0, -1)",
          msg(3)
        ),
        "n - 1..0//-1"
      )
    end
  end

  describe "range — realistic contexts" do
    test "in Enum.reduce_while" do
      confirm_fix(
        fix(
          "Enum.reduce_while(range(max_num, min_num - 1, -1), nil, fn i, _ ->",
          msg(3)
        ),
        "Enum.reduce_while(max_num..min_num - 1//-1, nil, fn i, _ ->"
      )
    end

    test "in assignment" do
      confirm_fix(
        fix(
          "nums = range(10, 0, -1)",
          msg(3)
        ),
        "nums = 10..0//-1"
      )
    end

    test "piped into Enum.map" do
      confirm_fix(
        fix(
          "range(0, 10, 2) |> Enum.map(&(&1 * 2))",
          msg(3)
        ),
        "0..10//2 |> Enum.map(&(&1 * 2))"
      )
    end

    test "preserves surrounding code" do
      input = """
      defmodule Palindrome do
        def largest(n) do
          max_num = Integer.pow(10, n) - 1
          min_num = Integer.pow(10, n - 1)

          Enum.reduce_while(range(max_num, min_num - 1, -1), 0, fn i, acc ->
            {:cont, max(acc, i)}
          end)
        end
      end
      """

      expected = """
      defmodule Palindrome do
        def largest(n) do
          max_num = Integer.pow(10, n) - 1
          min_num = Integer.pow(10, n - 1)

          Enum.reduce_while(max_num..min_num - 1//-1, 0, fn i, acc ->
            {:cont, max(acc, i)}
          end)
        end
      end
      """

      confirm_fix(fix(input, msg(3), 6), expected)
    end

    test "only fixes reported line" do
      input = """
      x = Enum.to_list(1..10)
      y = range(0, 5)
      """

      confirm_fix(fix(input, msg(2), 2), """
      x = Enum.to_list(1..10)
      y = 0..5 - 1
      """)
    end
  end
end
