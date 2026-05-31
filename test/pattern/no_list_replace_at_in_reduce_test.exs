defmodule Credence.Pattern.NoListReplaceAtInReduceTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListReplaceAtInReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListReplaceAtInReduce.check(ast, [])
  end

  describe "check" do
    # --- POSITIVE CASES ---

    test "flags List.replace_at on accumulator in Enum.reduce" do
      code = """
      defmodule Bad do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            List.replace_at(acc, i, i * 2)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_list_replace_at_in_reduce
      assert issue.message =~ "List.replace_at"
      assert issue.meta.line != nil
    end

    test "flags piped Enum.reduce" do
      code = """
      defmodule Bad do
        def update(list) do
          0..5
          |> Enum.reduce(list, fn i, acc ->
            List.replace_at(acc, i, i * 2)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
    end

    test "flags multiple List.replace_at calls on same accumulator" do
      code = """
      defmodule Bad do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            acc
            |> List.replace_at(i, i * 2)
            |> List.replace_at(i + 1, i * 3)
          end)
        end
      end
      """

      issues = check(code)
      # Should flag at least once (may report one per clause or one per call)
      assert length(issues) >= 1
      assert Enum.all?(issues, &(&1.rule == :no_list_replace_at_in_reduce))
    end

    test "flags when accumulator has different name" do
      code = """
      defmodule Bad do
        def update(list) do
          Enum.reduce(0..5, list, fn i, current ->
            List.replace_at(current, i, i * 2)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags List.update_at on accumulator in Enum.reduce" do
      code = """
      defmodule Bad do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            List.update_at(acc, i, fn _ -> i * 2 end)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
      assert hd(issues).message =~ "List.update_at"
    end

    test "flags piped List.update_at on accumulator in Enum.reduce" do
      code = """
      defmodule Bad do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            acc |> List.update_at(i, fn _ -> i * 2 end)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
    end

    test "flags List.update_at on accumulator in for reduce" do
      code = """
      defmodule Bad do
        def update(table) do
          for i <- 1..3, reduce: table do
            table ->
              List.update_at(table, i, fn _ -> i * 2 end)
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
      assert hd(issues).message =~ "List.update_at"
    end

    test "flags List.replace_at on accumulator in for reduce" do
      code = """
      defmodule Bad do
        def update(table) do
          for i <- 1..3, reduce: table do
            table ->
              List.replace_at(table, i, i * 2)
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
      assert hd(issues).message =~ "List.replace_at"
    end

    test "flags nested List.update_at on accumulator in for reduce" do
      code = """
      defmodule Bad do
        def update(table) do
          for i <- 1..3, reduce: table do
            table ->
              List.update_at(table, i, fn row ->
                List.update_at(row, 0, fn _ -> i end)
              end)
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
      assert Enum.all?(issues, &(&1.rule == :no_list_replace_at_in_reduce))
    end

    test "flags List.replace_at inside defp helper called from reduce" do
      code = """
      defmodule Bad do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            update_cell(acc, i, i * 2)
          end)
        end

        defp update_cell(list, idx, value) do
          List.replace_at(list, idx, value)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
      assert hd(issues).message =~ "List.replace_at"
    end

    test "flags piped List.replace_at inside defp helper called from reduce" do
      code = """
      defmodule Bad do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            update_cell(acc, i, i * 2)
          end)
        end

        defp update_cell(list, idx, value) do
          list |> List.replace_at(idx, value)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
    end

    test "flags List.update_at inside defp helper called from reduce" do
      code = """
      defmodule Bad do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            update_cell(acc, i, i * 2)
          end)
        end

        defp update_cell(list, idx, value) do
          List.update_at(list, idx, fn _ -> value end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
      assert hd(issues).message =~ "List.update_at"
    end

    test "flags nested List.replace_at inside defp helper called from reduce" do
      code = """
      defmodule Bad do
        def update(dp) do
          Enum.reduce(0..5, dp, fn i, dp ->
            update_dp(dp, i, i * 2)
          end)
        end

        defp update_dp(table, i, value) do
          row = Enum.at(table, i)
          new_row = List.replace_at(row, 0, value)
          List.replace_at(table, i, new_row)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
    end

    test "flags piped helper call: acc |> helper(...)" do
      code = """
      defmodule Bad do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            acc |> update_cell(i, i * 2)
          end)
        end

        defp update_cell(list, idx, value) do
          List.replace_at(list, idx, value)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
    end

    test "flags helper called from for reduce" do
      code = """
      defmodule Bad do
        def update(list) do
          for i <- 1..3, reduce: list do
            acc -> update_cell(acc, i, i * 2)
          end
        end

        defp update_cell(list, idx, value) do
          List.replace_at(list, idx, value)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_reduce
    end

    # --- NEGATIVE CASES ---

    test "does not flag List.replace_at on a different variable" do
      code = """
      defmodule Good do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            other = [1, 2, 3]
            List.replace_at(other, 0, 42)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag List.replace_at outside of Enum.reduce" do
      code = """
      defmodule Good do
        def update(list) do
          List.replace_at(list, 0, 42)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.put on accumulator" do
      code = """
      defmodule Good do
        def update(map) do
          Enum.reduce(0..5, map, fn i, acc ->
            Map.put(acc, i, i * 2)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag put_elem on accumulator" do
      code = """
      defmodule Good do
        def update(tuple) do
          Enum.reduce(0..5, tuple, fn i, acc ->
            put_elem(acc, i, i * 2)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag List.replace_at with non-matching first arg" do
      code = """
      defmodule Good do
        def update(list, other) do
          Enum.reduce(0..5, list, fn i, acc ->
            List.replace_at(other, i, 42)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map with List.replace_at" do
      code = """
      defmodule Good do
        def update(list) do
          Enum.map(list, fn x -> List.replace_at(x, 0, 42) end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag List.update_at on non-accumulator variable" do
      code = """
      defmodule Good do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            other = [1, 2, 3]
            List.update_at(other, 0, fn _ -> 42 end)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag List.update_at outside of reduce" do
      code = """
      defmodule Good do
        def update(list) do
          List.update_at(list, 0, fn _ -> 42 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.put on accumulator in for reduce" do
      code = """
      defmodule Good do
        def update(map) do
          for i <- 1..3, reduce: map do
            acc -> Map.put(acc, i, i * 2)
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag helper function that does not use List.replace_at" do
      code = """
      defmodule Good do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            log_value(acc, i)
          end)
        end

        defp log_value(list, idx) do
          IO.puts(Enum.at(list, idx))
          list
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag helper function with List.replace_at on non-first param" do
      code = """
      defmodule Good do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            transform(acc, i, [1, 2, 3])
          end)
        end

        defp transform(list, idx, items) do
          _unused = List.replace_at(items, 0, idx)
          list
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag helper called with accumulator as non-first arg" do
      code = """
      defmodule Good do
        def update(list) do
          Enum.reduce(0..5, list, fn i, acc ->
            transform(i, acc)
          end)
        end

        defp transform(idx, list) do
          List.replace_at(list, idx, 0)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag helper function called outside of reduce" do
      code = """
      defmodule Good do
        def update(list) do
          update_cell(list, 0, 42)
        end

        defp update_cell(list, idx, value) do
          List.replace_at(list, idx, value)
        end
      end
      """

      assert check(code) == []
    end
  end
end
