defmodule Credence.Pattern.NoManualListReverseTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualListReverse

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualListReverse.check(ast, [])
  end

  describe "NoManualListReverse" do
    test "detects the exact hand-rolled reverse pattern" do
      code = """
      defmodule Bad do
        def reverse_elements(list) when is_list(list) do
          do_reverse(list, [])
        end

        defp do_reverse([], acc), do: acc
        defp do_reverse([head | tail], acc) do
          do_reverse(tail, [head | acc])
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_list_reverse
      assert issue.message =~ "do_reverse/2"
      assert issue.message =~ "Enum.reverse"
    end

    test "detects with different function names" do
      code = """
      defmodule Bad do
        defp rev([], acc), do: acc
        defp rev([h | t], acc), do: rev(t, [h | acc])
      end
      """

      [issue] = check(code)
      assert issue.message =~ "rev/2"
    end

    test "detects with def (public) function" do
      code = """
      defmodule Bad do
        def my_reverse([], acc), do: acc
        def my_reverse([h | t], acc), do: my_reverse(t, [h | acc])
      end
      """

      [issue] = check(code)
      assert issue.message =~ "def my_reverse/2"
    end

    test "detects with clauses in reverse order" do
      code = """
      defmodule Bad do
        defp flip([h | t], acc), do: flip(t, [h | acc])
        defp flip([], acc), do: acc
      end
      """

      [issue] = check(code)
      assert issue.message =~ "flip/2"
    end

    test "detects with different parameter names" do
      code = """
      defmodule Bad do
        defp walk([], result), do: result
        defp walk([first | rest], result), do: walk(rest, [first | result])
      end
      """

      [issue] = check(code)
      assert issue.message =~ "walk/2"
    end

    # ---- Negative cases ----

    test "does not flag Enum.reverse/1 calls" do
      code = """
      defmodule Good do
        def reverse(list), do: Enum.reverse(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag when base case does not return accumulator" do
      code = """
      defmodule Good do
        defp walk([], _acc), do: []
        defp walk([h | t], acc), do: walk(t, [h | acc])
      end
      """

      assert check(code) == []
    end

    test "does not flag when recursive case transforms head" do
      code = """
      defmodule Good do
        defp double_and_reverse([], acc), do: acc
        defp double_and_reverse([h | t], acc), do: double_and_reverse(t, [h * 2 | acc])
      end
      """

      assert check(code) == []
    end

    test "does not flag when recursive case prepends to something other than acc" do
      code = """
      defmodule Good do
        defp interleave([], acc), do: acc
        defp interleave([h | t], acc), do: interleave(t, [h, h | acc])
      end
      """

      assert check(code) == []
    end

    test "does not flag single-clause functions" do
      code = """
      defmodule Good do
        defp walk([], acc), do: acc
      end
      """

      assert check(code) == []
    end

    test "does not flag functions with arity != 2" do
      code = """
      defmodule Good do
        defp reverse([]), do: []
        defp reverse([h | t]), do: reverse(t) ++ [h]
      end
      """

      assert check(code) == []
    end

    test "does not flag when recursive call does not match tail/head/acc shape" do
      code = """
      defmodule Good do
        defp walk([], acc), do: acc
        defp walk([h | t], acc), do: walk(t, acc ++ [h])
      end
      """

      assert check(code) == []
    end

    test "does not flag functions with more than 2 clauses" do
      code = """
      defmodule Good do
        defp walk([], acc), do: acc
        defp walk([single], acc), do: [single | acc]
        defp walk([h | t], acc), do: walk(t, [h | acc])
      end
      """

      assert check(code) == []
    end

    test "does not flag when the empty-list base case uses a guard" do
      code = """
      defmodule Good do
        defp walk([], acc) when is_list(acc), do: acc
        defp walk([h | t], acc), do: walk(t, [h | acc])
      end
      """

      # Guarded clauses change semantics — don't flag
      assert check(code) == []
    end

    test "does not flag when base case is not empty list" do
      code = """
      defmodule Good do
        defp walk([single], acc), do: [single | acc]
        defp walk([h | t], acc), do: walk(t, [h | acc])
      end
      """

      assert check(code) == []
    end
  end
end
