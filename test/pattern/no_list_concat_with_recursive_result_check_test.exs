defmodule Credence.Pattern.NoListConcatWithRecursiveResultCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoListConcatWithRecursiveResult

  describe "flags [literal] ++ recursive_result" do
    test "single-element literal ++ direct self-call" do
      code = """
      defmodule Bad do
        def build([]), do: []

        def build([h | t]) do
          [h] ++ build(t)
        end
      end
      """

      assert [%Issue{rule: :no_list_concat_with_recursive_result}] =
               check(NoListConcatWithRecursiveResult, code)
    end

    test "single-line clause with literal ++ self-call" do
      code = """
      defmodule Bad do
        def pre([]), do: []
        def pre([h | t]), do: [h, h * 2] ++ pre(t)
      end
      """

      assert [%Issue{rule: :no_list_concat_with_recursive_result}] =
               check(NoListConcatWithRecursiveResult, code)
    end

    test "literal ++ variable bound to a recursive call" do
      code = """
      defmodule Bad do
        def build([]), do: []

        def build([h | t]) do
          rest = build(t)
          [h] ++ rest
        end
      end
      """

      assert [%Issue{rule: :no_list_concat_with_recursive_result}] =
               check(NoListConcatWithRecursiveResult, code)
    end

    test "only the literal-prefix clause is flagged in a multi-clause function" do
      code = """
      defmodule Bad do
        defp flatten([], acc), do: acc

        defp flatten([h | t], acc) when is_list(h) do
          rest = flatten(t, acc)
          flatten(h, []) ++ rest
        end

        defp flatten([h | t], acc) do
          rest = flatten(t, acc)
          [h] ++ rest
        end
      end
      """

      # The `flatten(h, []) ++ rest` clause (recursion on the left) is NOT
      # flagged — only the `[h] ++ rest` clause is.
      assert [%Issue{rule: :no_list_concat_with_recursive_result}] =
               check(NoListConcatWithRecursiveResult, code)
    end
  end

  describe "does NOT flag (deliberately dropped — no safe local fix)" do
    test "computed variable ++ recursive result (the O(n^2) shape)" do
      # Left operand is an arbitrary bound list, not a literal: the only
      # behaviour-preserving fix is a non-local accumulator restructuring.
      code = """
      defmodule Safe do
        defp substrings(string, count, start_index) when start_index >= count, do: []

        defp substrings(string, count, start_index) do
          current =
            for len <- 1..(count - start_index) do
              String.slice(string, start_index, len)
            end

          rest = substrings(string, count, start_index + 1)
          current ++ rest
        end
      end
      """

      assert check(NoListConcatWithRecursiveResult, code) == []
    end

    test "recursive_result ++ [literal] (recursion on the left)" do
      # Cons only prepends; there is no `[... | ...]` form for an append.
      code = """
      defmodule Safe do
        def build([]), do: []

        def build([h | t]) do
          build(t) ++ [h]
        end
      end
      """

      assert check(NoListConcatWithRecursiveResult, code) == []
    end

    test "empty list literal ++ recursive result" do
      # `[] ++ rhs` is just `rhs`; there is no cons prefix to keep.
      code = """
      defmodule Safe do
        def build([]), do: []

        def build([_h | t]) do
          [] ++ build(t)
        end
      end
      """

      assert check(NoListConcatWithRecursiveResult, code) == []
    end

    test "non-recursive function" do
      code = """
      defmodule Safe do
        def combine(a, b), do: [1] ++ b
      end
      """

      assert check(NoListConcatWithRecursiveResult, code) == []
    end

    test "recursive function without ++ in return" do
      code = """
      defmodule Safe do
        def build([]), do: []
        def build([h | t]), do: [h | build(t)]
      end
      """

      assert check(NoListConcatWithRecursiveResult, code) == []
    end

    test "literal ++ literal, no recursive operand" do
      code = """
      defmodule Safe do
        def process(list) do
          _result = process(tl(list))
          [1, 2, 3] ++ [4, 5, 6]
        end
      end
      """

      assert check(NoListConcatWithRecursiveResult, code) == []
    end

    test "acc ++ [expr] in tail-call position" do
      code = """
      defmodule Safe do
        def build([h | t], acc), do: build(t, acc ++ [h])
        def build([], acc), do: acc
      end
      """

      # Handled by no_list_append_in_recursion, not here.
      assert check(NoListConcatWithRecursiveResult, code) == []
    end

    test "literal ++ recursive in non-return position" do
      code = """
      defmodule Safe do
        def process([]), do: []

        def process([h | t]) do
          combined = [h] ++ process(t)
          combined
        end
      end
      """

      assert check(NoListConcatWithRecursiveResult, code) == []
    end
  end
end
