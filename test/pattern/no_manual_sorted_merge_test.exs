defmodule Credence.Pattern.NoManualSortedMergeTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualSortedMerge

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualSortedMerge.check(ast, [])
  end

  describe "NoManualSortedMerge" do
    test "detects the classic sorted merge pattern" do
      code = """
      defmodule Bad do
        defp merge_sorted([], list2), do: list2
        defp merge_sorted(list1, []), do: list1
        defp merge_sorted([h1 | t1], [h2 | _] = list2) when h1 <= h2 do
          [h1 | merge_sorted(t1, list2)]
        end
        defp merge_sorted(list1, [h2 | t2]) do
          [h2 | merge_sorted(list1, t2)]
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_sorted_merge
      assert issue.message =~ "merge_sorted/2"
      assert issue.message =~ "Enum.sort"
    end

    test "detects with different function names" do
      code = """
      defmodule Bad do
        defp merge([], b), do: b
        defp merge(a, []), do: a
        defp merge([ha | ta], [hb | _] = b) when ha <= hb, do: [ha | merge(ta, b)]
        defp merge(a, [hb | tb]), do: [hb | merge(a, tb)]
      end
      """

      [issue] = check(code)
      assert issue.message =~ "merge/2"
    end

    test "detects with def (public) function" do
      code = """
      defmodule Bad do
        def merge([], list2), do: list2
        def merge(list1, []), do: list1
        def merge([h1 | t1], [h2 | _] = list2) when h1 <= h2 do
          [h1 | merge(t1, list2)]
        end
        def merge(list1, [h2 | t2]) do
          [h2 | merge(list1, t2)]
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "def merge/2"
    end

    test "detects with clauses in different order" do
      code = """
      defmodule Bad do
        defp merge([h1 | t1], [h2 | _] = list2) when h1 <= h2, do: [h1 | merge(t1, list2)]
        defp merge([], list2), do: list2
        defp merge(list1, [h2 | t2]), do: [h2 | merge(list1, t2)]
        defp merge(list1, []), do: list1
      end
      """

      [issue] = check(code)
      assert issue.message =~ "merge/2"
    end

    test "detects with different parameter names" do
      code = """
      defmodule Bad do
        defp interleave_sorted([], right), do: right
        defp interleave_sorted(left, []), do: left
        defp interleave_sorted([lh | lt], [rh | _] = right) when lh <= rh do
          [lh | interleave_sorted(lt, right)]
        end
        defp interleave_sorted(left, [rh | rt]) do
          [rh | interleave_sorted(left, rt)]
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "interleave_sorted/2"
    end

    # ---- Negative cases ----

    test "does not flag Enum.sort on concatenated lists" do
      code = """
      defmodule Good do
        def merge(list1, list2), do: Enum.sort(list1 ++ list2)
      end
      """

      assert check(code) == []
    end

    test "does not flag when fewer than 4 clauses" do
      code = """
      defmodule Good do
        defp merge([], list2), do: list2
        defp merge(list1, []), do: list1
        defp merge([h1 | t1], [h2 | _] = list2) when h1 <= h2, do: [h1 | merge(t1, list2)]
      end
      """

      assert check(code) == []
    end

    test "does not flag when base case returns fixed value" do
      code = """
      defmodule Good do
        defp merge([], _list2), do: []
        defp merge(_list1, []), do: []
        defp merge([h1 | t1], [h2 | _] = list2) when h1 <= h2, do: [h1 | merge(t1, list2)]
        defp merge(list1, [h2 | t2]), do: [h2 | merge(list1, t2)]
      end
      """

      assert check(code) == []
    end

    test "does not flag when recursive clause transforms head" do
      code = """
      defmodule Good do
        defp merge([], list2), do: list2
        defp merge(list1, []), do: list1
        defp merge([h1 | t1], [h2 | _] = list2) when h1 <= h2 do
          [h1 * 2 | merge(t1, list2)]
        end
        defp merge(list1, [h2 | t2]) do
          [h2 * 2 | merge(list1, t2)]
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when no guard on recursive clause" do
      code = """
      defmodule Good do
        defp weave([], list2), do: list2
        defp weave(list1, []), do: list1
        defp weave([h1 | t1], list2), do: [h1 | weave(t1, list2)]
        defp weave(list1, [h2 | t2]), do: [h2 | weave(list1, t2)]
      end
      """

      assert check(code) == []
    end

    test "does not flag when recursive call does not cons head" do
      code = """
      defmodule Good do
        defp merge([], list2), do: list2
        defp merge(list1, []), do: list1
        defp merge([h1 | t1], [h2 | _] = list2) when h1 <= h2 do
          merge(t1, list2)
        end
        defp merge(list1, [h2 | t2]) do
          merge(list1, t2)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag single-clause functions" do
      code = """
      defmodule Good do
        defp merge([], list2), do: list2
      end
      """

      assert check(code) == []
    end

    test "does not flag functions with arity != 2" do
      code = """
      defmodule Good do
        defp merge([]), do: []
        defp merge([h | t]), do: [h | merge(t)]
      end
      """

      assert check(code) == []
    end
  end
end
