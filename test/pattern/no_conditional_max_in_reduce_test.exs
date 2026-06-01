defmodule Credence.Pattern.NoConditionalMaxInReduceTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoConditionalMaxInReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoConditionalMaxInReduce.check(ast, [])
  end

  describe "NoConditionalMaxInReduce" do
    test "passes code that uses Enum.max/1 directly" do
      code = """
      defmodule GoodMax do
        def max_value(list) do
          Enum.max(list, fn -> 0 end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses simple max(acc, x) in reduce" do
      code = """
      defmodule GoodSimpleMax do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            max(x, acc)
          end)
        end
      end
      """

      # This is caught by no_explicit_max_reduce, not by this rule
      assert check(code) == []
    end

    test "detects max(acc, if cond do val else 0 end)" do
      code = """
      defmodule BadMaxIfZero do
        def max_kills(grid, row_counts, col_counts) do
          Enum.reduce(0..9, 0, fn col_idx, inner_max ->
            cell = Enum.at(grid, col_idx)
            kills =
              if cell == "0" do
                Enum.at(row_counts, col_idx) + Enum.at(col_counts, col_idx)
              else
                0
              end

            max(inner_max, kills)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_conditional_max_in_reduce
      assert issue.message =~ "Conditional max"
      assert issue.meta.line != nil
    end

    test "detects if cond do max(acc, val) else acc end" do
      code = """
      defmodule BadIfMaxAcc do
        def max_kills(grid) do
          Enum.reduce(0..9, 0, fn col_idx, inner_max ->
            cell = Enum.at(grid, col_idx)

            if cell == "0" do
              max(inner_max, Enum.at(grid, col_idx))
            else
              inner_max
            end
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_conditional_max_in_reduce
    end

    test "detects pattern in nested reduce" do
      code = """
      defmodule NestedReduce do
        def max_kills(grid, row_counts, col_counts) do
          Enum.reduce(0..2, 0, fn row_idx, current_max ->
            Enum.reduce(0..3, current_max, fn col_idx, inner_max ->
              cell = grid |> Enum.at(row_idx) |> Enum.at(col_idx)

              kills =
                if cell == "0" do
                  Enum.at(Enum.at(row_counts, row_idx), col_idx) +
                    Enum.at(Enum.at(col_counts, col_idx), row_idx)
                else
                  0
                end

              max(inner_max, kills)
            end)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      assert Enum.any?(issues, &(&1.rule == :no_conditional_max_in_reduce))
    end

    test "does NOT detect reduce with sum (not max)" do
      code = """
      defmodule GoodSum do
        def count(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if x > 0, do: acc + 1, else: acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect conditional max with non-zero else" do
      code = """
      defmodule GoodNonZeroElse do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            val = if x > 5, do: x, else: -1
            max(acc, val)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect non-reduce max" do
      code = """
      defmodule NoReduce do
        def compare(a, b) do
          val = if a > 0, do: b, else: 0
          max(a, val)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect reduce where condition does not involve max" do
      code = """
      defmodule GoodConditionalNotMax do
        def process(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if x > 0 do
              acc + x
            else
              acc
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect max with conditional that has multiple statements in branch" do
      code = """
      defmodule GoodMultiStatement do
        def process(list) do
          Enum.reduce(list, 0, fn x, acc ->
            val = if x > 0 do
              IO.puts(x)
              x
            else
              0
            end
            max(acc, val)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects multiple conditional max reduces" do
      code = """
      defmodule MultipleBad do
        def process(a, b) do
          x = Enum.reduce(a, 0, fn v, acc ->
            val = if v > 0, do: v, else: 0
            max(acc, val)
          end)

          y = Enum.reduce(b, 0, fn v, acc ->
            val = if v > 0, do: v, else: 0
            max(acc, val)
          end)

          {x, y}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end
  end
end
