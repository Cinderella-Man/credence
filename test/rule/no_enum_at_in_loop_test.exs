defmodule Credence.Rule.NoEnumAtInLoopTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoEnumAtInLoop.check(ast, [])
  end

  describe "NoEnumAtInLoop" do
    test "passes Enum.at outside of any loop" do
      code = """
      defmodule Safe do
        def third(list) do
          Enum.at(list, 2)
        end
      end
      """

      assert check(code) == []
    end

    test "passes pattern matching in recursion" do
      code = """
      defmodule Good do
        def sum([]), do: 0
        def sum([head | tail]), do: head + sum(tail)
      end
      """

      assert check(code) == []
    end

    test "passes Enum.with_index in reduce" do
      code = """
      defmodule Good do
        def indexed_sum(list) do
          list
          |> Stream.with_index()
          |> Enum.reduce(0, fn {val, _idx}, acc -> acc + val end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects Enum.at inside Enum.reduce" do
      code = """
      defmodule Bad do
        def sum_indices(list, indices) do
          Enum.reduce(indices, 0, fn i, acc ->
            acc + Enum.at(list, i)
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_enum_at_in_loop

      assert issue.message =~ "Enum.at/2"
      assert issue.meta.line != nil
    end

    test "detects Enum.at inside Enum.map" do
      code = """
      defmodule Bad do
        def get_elements(list, indices) do
          Enum.map(indices, fn i -> Enum.at(list, i) end)
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      assert hd(issues).rule == :no_enum_at_in_loop
    end

    test "detects Enum.at inside for comprehension" do
      code = """
      defmodule Bad do
        def get_elements(list, n) do
          for i <- 0..(n - 1), do: Enum.at(list, i)
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      assert hd(issues).rule == :no_enum_at_in_loop
    end

    test "detects Enum.at inside recursive function" do
      code = """
      defmodule BadPalindrome do
        defp do_palindrome?(graphemes, start, stop) do
          left = Enum.at(graphemes, start)
          right = Enum.at(graphemes, stop)
          left == right and do_palindrome?(graphemes, start + 1, stop - 1)
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      assert hd(issues).rule == :no_enum_at_in_loop
    end

    test "detects Enum.at inside guarded recursive function" do
      code = """
      defmodule BadExpand do
        defp expand(graphemes, left, right, count) when left >= 0 and right < count do
          if Enum.at(graphemes, left) == Enum.at(graphemes, right) do
            1 + expand(graphemes, left - 1, right + 1, count)
          else
            0
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      assert hd(issues).rule == :no_enum_at_in_loop
    end

    test "ignores Enum.at in non-recursive function" do
      code = """
      defmodule Safe do
        def middle(list) do
          mid = div(length(list), 2)
          Enum.at(list, mid)
        end
      end
      """

      assert check(code) == []
    end

    test "deduplicates Enum.at calls on the same line in recursive body" do
      code = """
      defmodule Bad do
        defp check(g, l, r) do
          Enum.at(g, l) == Enum.at(g, r) and check(g, l + 1, r - 1)
        end
      end
      """

      issues = check(code)

      # Two Enum.at calls on same line are deduplicated to one
      assert length(issues) == 1
    end
  end
end
