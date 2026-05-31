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
  end
end
