defmodule Credence.Pattern.NoMultipleEnumAtFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoMultipleEnumAt

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoMultipleEnumAt.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoMultipleEnumAt, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "fixes contiguous sequential positive indices" do
      input = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 1)
          c = Enum.at(list, 2)
          {a, b, c}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          [a, b, c | _] = list
          {a, b, c}
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes contiguous positive indices with small gaps" do
      input = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 2)
          c = Enum.at(list, 3)
          {a, b, c}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          [a, _, b, c | _] = list
          {a, b, c}
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes contiguous negative indices" do
      input = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, -1)
          b = Enum.at(list, -2)
          c = Enum.at(list, -3)
          {a, b, c}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          [a, b, c | _] = Enum.reverse(list)
          {a, b, c}
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes mixed positive and negative indices" do
      input = """
      defmodule Example do
        def run(sorted) do
          min1 = Enum.at(sorted, 0)
          min2 = Enum.at(sorted, 1)
          max1 = Enum.at(sorted, -1)
          max2 = Enum.at(sorted, -2)
          {min1, min2, max1, max2}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(sorted) do
          [min1, min2 | _] = sorted
          [max1, max2 | _] = Enum.reverse(sorted)
          {min1, min2, max1, max2}
        end
      end
      """

      assert fix(input) == expected
    end

    test "returns source unchanged when nothing to fix" do
      source = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 1)
          {a, b}
        end
      end
      """

      assert fix(source) == source
    end

    test "does not fix sparse indices" do
      source = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          b = Enum.at(list, 100)
          c = Enum.at(list, 200)
          {a, b, c}
        end
      end
      """

      assert fix(source) == source
    end

    test "fixes contiguous subset when separated by other code" do
      input = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          IO.puts(a)
          b = Enum.at(list, 1)
          c = Enum.at(list, 2)
          d = Enum.at(list, 3)
          {a, b, c, d}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          a = Enum.at(list, 0)
          IO.puts(a)
          [_, b, c, d | _] = list
          {a, b, c, d}
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves surrounding code" do
      input = """
      defmodule Example do
        def run(list) do
          before = :ok
          a = Enum.at(list, 0)
          b = Enum.at(list, 1)
          c = Enum.at(list, 2)
          after_val = :done
          {before, a, b, c, after_val}
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          before = :ok
          [a, b, c | _] = list
          after_val = :done
          {before, a, b, c, after_val}
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixes the documentation example end-to-end" do
      input = """
      defmodule Example do
        def extremes(nums) do
          sorted = Enum.sort(nums)
          min1 = Enum.at(sorted, 0)
          min2 = Enum.at(sorted, 1)
          max1 = Enum.at(sorted, -1)
          max2 = Enum.at(sorted, -2)
          max(min1 * min2, max1 * max2)
        end
      end
      """

      expected = """
      defmodule Example do
        def extremes(nums) do
          sorted = Enum.sort(nums)
          [min1, min2 | _] = sorted
          [max1, max2 | _] = Enum.reverse(sorted)
          max(min1 * min2, max1 * max2)
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixed code has fewer check issues" do
      source = """
      defmodule Example do
        def run(sorted) do
          min1 = Enum.at(sorted, 0)
          min2 = Enum.at(sorted, 1)
          max1 = Enum.at(sorted, -1)
          max2 = Enum.at(sorted, -2)
          {min1, min2, max1, max2}
        end
      end
      """

      issues_before = check(source)
      refute Enum.empty?(issues_before)

      issues_after = check(fix(source))
      assert length(issues_after) < length(issues_before)
    end
  end
end
