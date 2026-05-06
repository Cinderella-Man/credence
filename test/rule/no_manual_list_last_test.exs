defmodule Credence.Pattern.NoManualListLastTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoManualListLast.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoManualListLast.fix(code, [])
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

  describe "fix" do
    test "replaces hand-rolled function with List.last delegation" do
      code = """
      defmodule Bad do
        defp get_last_element([val]), do: val
        defp get_last_element([_ | rest]), do: get_last_element(rest)
      end
      """

      fixed = fix(code)

      assert fixed =~ "get_last_element(list)"
      assert fixed =~ "List.last(list)"
      refute fixed =~ "[_ | rest]"
    end

    test "fix produces valid Elixir code" do
      code = """
      defmodule Bad do
        defp get_last_element([val]), do: val
        defp get_last_element([_ | rest]), do: get_last_element(rest)

        def run(list), do: get_last_element(list)
      end
      """

      fixed = fix(code)
      assert {:ok, _ast} = Code.string_to_quoted(fixed)
    end

    test "replaces direct calls to the function" do
      code = """
      defmodule Bad do
        defp get_last_element([val]), do: val
        defp get_last_element([_ | rest]), do: get_last_element(rest)

        def run(list), do: get_last_element(list)
      end
      """

      fixed = fix(code)

      assert length(Regex.scan(~r/List\.last/, fixed)) >= 2
    end

    test "replaces pipe calls" do
      code = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list), do: list |> last()
      end
      """

      fixed = fix(code)

      assert fixed =~ "List.last()"
    end

    test "does not modify code without the pattern" do
      code = """
      defmodule Good do
        def run(list), do: List.last(list)
      end
      """

      assert fix(code) == code
    end

    test "handles clauses in reverse order" do
      code = """
      defmodule Bad do
        defp my_last([_ | rest]), do: my_last(rest)
        defp my_last([val]), do: val
      end
      """

      fixed = fix(code)

      assert fixed =~ "defp my_last(list)"
      assert fixed =~ "List.last(list)"
      refute fixed =~ "[_ | rest]"
    end

    test "handles def (public) functions" do
      code = """
      defmodule Bad do
        def final([el]), do: el
        def final([_ | rest]), do: final(rest)
      end
      """

      fixed = fix(code)

      assert fixed =~ "def final(list)"
      assert fixed =~ "List.last(list)"
      refute fixed =~ "[_ | rest]"
    end

    test "handles function called inside nested expression" do
      code = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list), do: {last(list), :ok}
      end
      """

      fixed = fix(code)

      assert fixed =~ "List.last(list)"
    end

    test "handles function called inside fn" do
      code = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(lists), do: Enum.map(lists, fn x -> last(x) end)
      end
      """

      fixed = fix(code)

      assert fixed =~ "List.last(x)"
    end

    test "handles function called inside case" do
      code = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list) do
          case :ok do
            :ok -> last(list)
            _ -> nil
          end
        end
      end
      """

      fixed = fix(code)

      assert fixed =~ "List.last(list)"
    end

    test "handles multiple matching functions" do
      code = """
      defmodule Bad do
        defp last_a([val]), do: val
        defp last_a([_ | rest]), do: last_a(rest)

        defp last_b([val]), do: val
        defp last_b([_ | rest]), do: last_b(rest)
      end
      """

      fixed = fix(code)

      assert fixed =~ "defp last_a(list)"
      assert fixed =~ "defp last_b(list)"
      refute fixed =~ "[_ | rest]"
    end

    test "preserves other functions in the module" do
      code = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def other(x), do: x + 1
      end
      """

      fixed = fix(code)

      assert fixed =~ "def other(x)"
      assert fixed =~ "x + 1"
    end

    test "returns original source when no matches found" do
      code = """
      defmodule Good do
        def run(list), do: hd(list)
      end
      """

      assert fix(code) == code
    end

    test "handles longer pipeline before the function call" do
      code = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list), do:
          list
          |> Enum.map(&(&1))
          |> last()
      end
      """

      fixed = fix(code)

      assert fixed =~ "List.last()"
    end

    test "handles function with non-adjacent clauses" do
      code = """
      defmodule Bad do
        defp last([val]), do: val
        def other(x), do: x + 1
        defp last([_ | rest]), do: last(rest)
      end
      """

      fixed = fix(code)

      assert fixed =~ "defp last(list)"
      assert fixed =~ "List.last(list)"
      assert fixed =~ "def other(x)"
      refute fixed =~ "[_ | rest]"
    end

    test "handles function called in a tuple" do
      code = """
      defmodule Bad do
        defp last([val]), do: val
        defp last([_ | rest]), do: last(rest)

        def run(list), do: {last(list), last(list)}
      end
      """

      fixed = fix(code)

      assert length(Regex.scan(~r/List\.last/, fixed)) >= 3
    end

    test "does not affect functions with similar but different patterns" do
      code = """
      defmodule Good do
        defp sum([val]), do: val
        defp sum([head | rest]), do: head + sum(rest)

        def run(list), do: sum(list)
      end
      """

      fixed = fix(code)

      assert fixed =~ "sum(list)"
      refute fixed =~ "List.last"
    end
  end
end
