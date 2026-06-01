defmodule Credence.Pattern.NoManualFindTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualFind

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualFind.check(ast, [])
  end

  describe "NoManualFind" do
    # ---- Positive cases ----

    test "detects the exact hand-rolled find pattern (arity 1)" do
      code = """
      defmodule Bad do
        def last_odd(numbers) do
          numbers
          |> Enum.reverse()
          |> find_last_odd()
        end

        defp find_last_odd([]), do: -1
        defp find_last_odd([head | _tail]) when rem(head, 2) != 0, do: head
        defp find_last_odd([_head | tail]), do: find_last_odd(tail)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_find
      assert issue.message =~ "find_last_odd/1"
      assert issue.message =~ "Enum.find/3"
    end

    test "detects arity 2 variant" do
      code = """
      defmodule Bad do
        defp find_first([], default), do: default
        defp find_first([h | _t], _default) when rem(h, 2) != 0, do: h
        defp find_first([_ | t], default), do: find_first(t, default)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_find
      assert issue.message =~ "find_first/2"
    end

    test "detects with different function names" do
      code = """
      defmodule Bad do
        defp get_odd([]), do: nil
        defp get_odd([h | _]) when rem(h, 2) != 0, do: h
        defp get_odd([_ | t]), do: get_odd(t)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "get_odd/1"
    end

    test "detects with def (public) function" do
      code = """
      defmodule Bad do
        def find_positive([]), do: nil
        def find_positive([h | _]) when h > 0, do: h
        def find_positive([_ | t]), do: find_positive(t)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "def find_positive/1"
    end

    test "detects with clauses in different order" do
      code = """
      defmodule Bad do
        defp find([h | _t]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
        defp find([]), do: nil
      end
      """

      [issue] = check(code)
      assert issue.message =~ "find/1"
    end

    # ---- Negative cases ----

    test "does not flag Enum.find/3 calls" do
      code = """
      defmodule Good do
        def find_odd(list), do: Enum.find(list, -1, &(rem(&1, 2) != 0))
      end
      """

      assert check(code) == []
    end

    test "does not flag when match clause has no guard" do
      code = """
      defmodule Good do
        defp find([]), do: nil
        defp find([:target | _]), do: :found
        defp find([_ | t]), do: find(t)
      end
      """

      # No guard on the match clause — not a predicate-based find
      assert check(code) == []
    end

    test "does not flag when match clause transforms head" do
      code = """
      defmodule Good do
        defp find([]), do: -1
        defp find([h | _]) when h > 0, do: h * 2
        defp find([_ | t]), do: find(t)
      end
      """

      # Returns h * 2, not just h — not a plain find
      assert check(code) == []
    end

    test "does not flag when recurse clause does not call self" do
      code = """
      defmodule Good do
        defp find([]), do: -1
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]), do: other(t)
      end
      """

      # Recursive clause calls other/1, not find/1
      assert check(code) == []
    end

    test "does not flag functions with arity 3" do
      code = """
      defmodule Good do
        defp find([], a, _b), do: a
        defp find([h | _], _a, _b) when h > 0, do: h
        defp find([_ | t], a, b), do: find(t, a, b)
      end
      """

      assert check(code) == []
    end

    test "does not flag 2-clause functions" do
      code = """
      defmodule Good do
        defp find([]), do: -1
        defp find([h | _]) when h > 0, do: h
      end
      """

      assert check(code) == []
    end

    test "does not flag 4-clause functions" do
      code = """
      defmodule Good do
        defp find([]), do: -1
        defp find([h | _]) when h > 0, do: h
        defp find([h | _]) when h < -10, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      assert check(code) == []
    end

    test "does not flag when base case is not empty list" do
      code = """
      defmodule Good do
        defp find([single]), do: single
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      # Base case matches [single], not []
      assert check(code) == []
    end

    test "does not flag when base case body is a recursive call" do
      code = """
      defmodule Good do
        defp find([]), do: find([0])
        defp find([h | _]) when h > 0, do: h
        defp find([_ | t]), do: find(t)
      end
      """

      # Base case recurses — not a find pattern
      assert check(code) == []
    end
  end
end
