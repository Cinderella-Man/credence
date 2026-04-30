defmodule Credence.Rule.NoEnumAtBinarySearchTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoEnumAtBinarySearch.check(ast, [])
  end

  describe "NoEnumAtBinarySearch" do
    test "flags Enum.at/2 in binary-search-like pattern" do
      code = """
      defmodule BinarySearch do
        def search(list, target, low, high) when low <= high do
          mid = low + div(high - low, 2)
          mid_val = Enum.at(list, mid)

          cond do
            mid_val == target -> :found
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
    end

    test "passes code using List.to_tuple and elem" do
      code = """
      defmodule FastSearch do
        def search(list, target) do
          tuple = List.to_tuple(list)
          do_search(tuple, target, 0, tuple_size(tuple) - 1)
        end

        defp do_search(tuple, target, low, high) do
          mid = div(low + high, 2)
          mid_val = elem(tuple, mid) # This is O(1)
        end
      end
      """

      assert check(code) == []
    end

    test "ignores Enum.at/2 with literal integers (likely not a search loop)" do
      code = """
      defmodule Config do
        def first_three(list) do
          {Enum.at(list, 0), Enum.at(list, 1), Enum.at(list, 2)}
        end
      end
      """

      # While Enum.at(list, 0) is still technically slower than hd(list),
      # it's not the "Binary Search Trap" we are targeting here.
      assert check(code) == []
    end

    test "does not flag Enum.at/2 with simple dynamic index" do
      code = """
      defmodule Example do
        def get(list, i) do
          Enum.at(list, i)
        end
      end
      """

      assert check(code) == []
    end
  end

  test "flags Enum.at/2 when midpoint expression is inline" do
    code = """
    defmodule Inline do
      def search(list, low, high) do
        Enum.at(list, low + div(high - low, 2))
      end
    end
    """

    assert length(check(code)) == 1
  end

  test "does not flag when variable is not derived from midpoint math" do
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
