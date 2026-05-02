defmodule Credence.Rule.NoManualListLastTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoManualListLast.check(ast, [])
  end

  describe "NoManualListLast" do
    test "detects the exact hand-rolled pattern" do
      code = """
      defmodule Bad do
        defp get_last_element([val]), do: val
        defp get_last_element([_ | rest]), do: get_last_element(rest)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_list_last

      assert issue.message =~ "get_last_element/1"
      assert issue.message =~ "List.last/1"
    end

    test "detects with different function name" do
      code = """
      defmodule Bad do
        defp last_item([x]), do: x
        defp last_item([_ | t]), do: last_item(t)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "last_item/1"
    end

    test "detects with underscore-prefixed head variable" do
      code = """
      defmodule Bad do
        defp tail_val([v]), do: v
        defp tail_val([_head | rest]), do: tail_val(rest)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "tail_val/1"
    end

    test "detects with def (not just defp)" do
      code = """
      defmodule Bad do
        def final([el]), do: el
        def final([_ | rest]), do: final(rest)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "def final/1"
    end

    test "detects with clauses in reverse order" do
      code = """
      defmodule Bad do
        defp my_last([_ | rest]), do: my_last(rest)
        defp my_last([val]), do: val
      end
      """

      [issue] = check(code)
      assert issue.message =~ "my_last/1"
    end

    # ---- Negative cases ----

    test "does not flag List.last/1 calls (different rule)" do
      code = """
      defmodule Good do
        def final(list), do: List.last(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag functions with more than 2 clauses" do
      code = """
      defmodule Good do
        defp process([]), do: nil
        defp process([val]), do: val
        defp process([_ | rest]), do: process(rest)
      end
      """

      assert check(code) == []
    end

    test "does not flag guarded clauses" do
      code = """
      defmodule Good do
        defp find_last([val]) when is_integer(val), do: val
        defp find_last([_ | rest]), do: find_last(rest)
      end
      """

      assert check(code) == []
    end

    test "does not flag when base case returns something other than the variable" do
      code = """
      defmodule Good do
        defp count([_val]), do: 1
        defp count([_ | rest]), do: 1 + count(rest)
      end
      """

      assert check(code) == []
    end

    test "does not flag when recursive case does more than recurse" do
      code = """
      defmodule Good do
        defp sum([val]), do: val
        defp sum([head | rest]), do: head + sum(rest)
      end
      """

      assert check(code) == []
    end

    test "does not flag when head is used (not ignored)" do
      code = """
      defmodule Good do
        defp find([val]), do: val
        defp find([head | rest]), do: max(head, find(rest))
      end
      """

      assert check(code) == []
    end

    test "does not flag multi-arity functions" do
      code = """
      defmodule Good do
        defp walk([val], _acc), do: val
        defp walk([_ | rest], acc), do: walk(rest, acc)
      end
      """

      assert check(code) == []
    end

    test "does not flag functions that don't recurse" do
      code = """
      defmodule Good do
        defp extract([val]), do: val
        defp extract([_ | rest]), do: hd(rest)
      end
      """

      assert check(code) == []
    end

    test "does not flag pattern matching on non-list arguments" do
      code = """
      defmodule Good do
        defp unwrap({:ok, val}), do: val
        defp unwrap({:error, _}), do: nil
      end
      """

      assert check(code) == []
    end
  end
end
