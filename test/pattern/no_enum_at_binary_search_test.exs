defmodule Credence.Pattern.NoEnumAtBinarySearchTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumAtBinarySearch

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEnumAtBinarySearch.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoEnumAtBinarySearch, code, [])
  end

  describe "detects recursive binary search patterns" do
    test "flags recursive function with Enum.at and mid from low + div(high - low, 2)" do
      code = """
      defmodule Search do
        def search(list, target, low, high) when low <= high do
          mid = low + div(high - low, 2)
          mid_val = Enum.at(list, mid)

          cond do
            mid_val == target -> mid
            mid_val < target -> search(list, target, mid + 1, high)
            true -> search(list, target, low, mid - 1)
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_enum_at_binary_search
      assert issue.message =~ "List.to_tuple/1"
      assert issue.meta.line != nil
    end

    test "flags recursive function with mid from div(low + high, 2)" do
      code = """
      defmodule Search do
        def search(list, target, low, high) when low <= high do
          mid = div(low + high, 2)
          mid_val = Enum.at(list, mid)

          cond do
            mid_val == target -> mid
            mid_val < target -> search(list, target, mid + 1, high)
            true -> search(list, target, low, mid - 1)
          end
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags recursive defp with piped Enum.at" do
      code = """
      defmodule Search do
        defp do_search(list, target, low, high) when low <= high do
          mid = low + div(high - low, 2)
          mid_val = list |> Enum.at(mid)

          cond do
            mid_val == target -> mid
            mid_val < target -> do_search(list, target, mid + 1, high)
            true -> do_search(list, target, low, mid - 1)
          end
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags recursive function with inline midpoint" do
      code = """
      defmodule Search do
        def search(list, target, low, high) when low <= high do
          mid_val = Enum.at(list, low + div(high - low, 2))

          cond do
            mid_val == target -> :found
            mid_val < target -> search(list, target, low + 1, high)
            true -> search(list, target, low, high - 1)
          end
        end
      end
      """

      assert length(check(code)) == 1
    end

    test "flags multiple Enum.at calls in recursive function" do
      code = """
      defmodule BinarySearch do
        def find_first(list, target, low, high) when low <= high do
          mid = div(low + high, 2)
          mid_val = Enum.at(list, mid)

          cond do
            mid_val < target -> find_first(list, target, mid + 1, high)
            mid_val > target -> find_first(list, target, low, mid - 1)
            true ->
              earlier = find_first(list, target, low, mid - 1)
              if earlier == -1, do: mid, else: earlier
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_at_binary_search
    end
  end

  describe "ignores non-recursive functions" do
    test "does not flag non-recursive function with Enum.at and midpoint" do
      code = """
      defmodule NonRecursive do
        def find(list, low, high) do
          mid = low + div(high - low, 2)
          Enum.at(list, mid)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag reduce_while pattern (non-recursive enclosing def)" do
      code = """
      defmodule Iterative do
        def search(list, target) do
          Enum.reduce_while(0..100, {0, length(list) - 1}, fn _, {low, high} ->
            mid = low + div(high - low, 2)
            mid_val = Enum.at(list, mid)

            cond do
              mid_val == target -> {:halt, {:ok, mid}}
              mid_val < target -> {:cont, {mid + 1, high}}
              true -> {:cont, {low, mid - 1}}
            end
          end)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "ignores safe code" do
    test "passes code using elem/tuple" do
      code = """
      defmodule Fast do
        defp do_search(tuple, target, low, high) when low <= high do
          mid = div(low + high, 2)
          mid_val = elem(tuple, mid)

          cond do
            mid_val == target -> mid
            mid_val < target -> do_search(tuple, target, mid + 1, high)
            true -> do_search(tuple, target, low, mid - 1)
          end
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.at with literal indices" do
      code = """
      defmodule Config do
        def first_three(list) do
          {Enum.at(list, 0), Enum.at(list, 1), Enum.at(list, 2)}
        end
      end
      """

      assert check(code) == []
    end

    test "passes Enum.at with simple dynamic index" do
      code = """
      defmodule Example do
        def get(list, i) do
          Enum.at(list, i)
        end
      end
      """

      assert check(code) == []
    end

    test "passes when mid is a parameter, not derived from midpoint math" do
      code = """
      defmodule Example do
        def foo(list, mid) do
          Enum.at(list, mid)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "check-only: no auto-fix" do
    test "fix returns source unchanged" do
      code = """
      defmodule Search do
        def search(list, target, low, high) when low <= high do
          mid = div(low + high, 2)
          mid_val = Enum.at(list, mid)

          cond do
            mid_val == target -> mid
            mid_val < target -> search(list, target, mid + 1, high)
            true -> search(list, target, low, mid - 1)
          end
        end
      end
      """

      result = fix(code)
      assert result == code
    end
  end
end
