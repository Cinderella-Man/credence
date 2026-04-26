defmodule Credence.Rule.NoEnumAtInLoopTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoEnumAtInLoop.check(ast, [])
  end

  describe "NoEnumAtInLoop" do
    test "detects Enum.at inside Enum.reduce" do
      code = """
      defmodule Bad do
        def sum_evens(list) do
          n = length(list)
          Enum.reduce(0..(n - 1), 0, fn i, acc ->
            val = Enum.at(list, i)
            if rem(val, 2) == 0, do: acc + val, else: acc
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_at_in_loop
      assert issue.severity == :warning
      assert issue.message =~ "Enum.at"
      assert issue.message =~ "O(n"
    end

    test "detects Enum.at inside Enum.map" do
      code = """
      defmodule Bad do
        def pairs(list) do
          Enum.map(0..(length(list) - 2), fn i ->
            {Enum.at(list, i), Enum.at(list, i + 1)}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
    end

    test "detects Enum.at inside Enum.take_while" do
      code = """
      defmodule Bad do
        def palindrome?(graphemes, start, len) do
          half = div(len, 2)
          0..(half - 1)
          |> Enum.take_while(fn i ->
            Enum.at(graphemes, start + i) == Enum.at(graphemes, start + len - 1 - i)
          end)
          |> length() == half
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
    end

    test "detects Enum.at inside Enum.any?" do
      code = """
      defmodule Bad do
        def has_pair?(list) do
          Enum.any?(0..(length(list) - 2), fn i ->
            Enum.at(list, i) == Enum.at(list, i + 1)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
    end

    test "detects Enum.at inside Enum.all?" do
      code = """
      defmodule Bad do
        def sorted?(list) do
          Enum.all?(0..(length(list) - 2), fn i ->
            Enum.at(list, i) <= Enum.at(list, i + 1)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) >= 1
    end

    test "detects Enum.at inside Enum.filter" do
      code = """
      defmodule Bad do
        def pick_indices(list, indices) do
          Enum.filter(indices, fn i ->
            Enum.at(list, i) > 0
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.at"
    end

    test "detects Enum.at inside Enum.each" do
      code = """
      defmodule Bad do
        def print_items(list) do
          Enum.each(0..(length(list) - 1), fn i ->
            IO.puts(Enum.at(list, i))
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_at_in_loop
    end

    test "detects Enum.at inside Enum.reduce_while" do
      code = """
      defmodule Bad do
        def find_first_positive(list) do
          Enum.reduce_while(0..(length(list) - 1), nil, fn i, _acc ->
            val = Enum.at(list, i)
            if val > 0, do: {:halt, val}, else: {:cont, nil}
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_at_in_loop
    end

    test "detects piped Enum.at inside loop" do
      code = """
      defmodule Bad do
        def process(list) do
          0..(length(list) - 1)
          |> Enum.map(fn i ->
            list |> Enum.at(i) |> to_string()
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_enum_at_in_loop
    end

    # ---- Negative cases ----

    test "does not flag Enum.at outside of loops" do
      code = """
      defmodule Good do
        def first(list), do: Enum.at(list, 0)
        def third(list), do: Enum.at(list, 2)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.map without Enum.at" do
      code = """
      defmodule Good do
        def double(list) do
          Enum.map(list, fn x -> x * 2 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.reduce without Enum.at" do
      code = """
      defmodule Good do
        def sum(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.get inside loop (not Enum.at)" do
      code = """
      defmodule Good do
        def lookup(keys, map) do
          Enum.map(keys, fn k -> Map.get(map, k) end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.with_index pattern (correct approach)" do
      code = """
      defmodule Good do
        def indexed(list) do
          list
          |> Enum.with_index()
          |> Enum.map(fn {val, idx} -> {idx, val} end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
