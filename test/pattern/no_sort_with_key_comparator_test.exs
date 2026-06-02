defmodule Credence.Pattern.NoSortWithKeyComparatorTest do
  use ExUnit.Case

  alias Credence.Pattern.NoSortWithKeyComparator

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoSortWithKeyComparator.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoSortWithKeyComparator, code, [])
  end

  # ── check — positive cases ─────────────────────────────────────

  describe "check — positive cases" do
    test "flags sort with 3-tuple ascending < comparator" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list, fn {_, _, w1}, {_, _, w2} -> w1 < w2 end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_sort_with_key_comparator
      assert issue.message =~ "Enum.sort_by"
      assert issue.message =~ "2"
    end

    test "flags sort with 2-tuple ascending < comparator" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list, fn {a, _}, {b, _} -> a < b end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_sort_with_key_comparator
      assert issue.message =~ "0"
    end

    test "flags sort with <= comparator" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list, fn {_, a}, {_, b} -> a <= b end)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Enum.sort_by"
    end

    test "flags sort with descending > comparator" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list, fn {a, _}, {b, _} -> a > b end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_sort_with_key_comparator
    end

    test "flags sort with descending >= comparator" do
      code = """
      defmodule Bad do
        def f(list), do: Enum.sort(list, fn {a, _}, {b, _} -> a >= b end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_sort_with_key_comparator
    end

    test "flags sort in pipe" do
      code = """
      defmodule Bad do
        def f(list), do: list |> Enum.sort(fn {_, _, w1}, {_, _, w2} -> w1 < w2 end)
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_sort_with_key_comparator
    end

    test "flags multiple occurrences" do
      code = """
      defmodule Bad do
        def f(a, b) do
          x = Enum.sort(a, fn {_, w}, {_, w2} -> w < w2 end)
          y = Enum.sort(b, fn {k, _}, {k2, _} -> k < k2 end)
          {x, y}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end
  end

  # ── check — negative cases ─────────────────────────────────────

  describe "check — negative cases" do
    test "does not flag sort with plain args (no tuple destructuring)" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list, fn a, b -> a < b end)
      end
      """

      assert check(code) == []
    end

    test "does not flag sort with multiple vars in tuple" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list, fn {a, b}, {c, d} -> a < c end)
      end
      """

      assert check(code) == []
    end

    test "does not flag sort with complex body" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list, fn {_, _, w1}, {_, _, w2} -> w1 < w2 or w1 == w2 end)
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort_by" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort_by(list, &elem(&1, 2))
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.sort/1" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag reversed variable order in body" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list, fn {_, _, w1}, {_, _, w2} -> w2 < w1 end)
      end
      """

      assert check(code) == []
    end

    test "does not flag mismatched tuple sizes" do
      code = """
      defmodule Good do
        def f(list), do: Enum.sort(list, fn {a, _}, {b, _, _} -> a < b end)
      end
      """

      assert check(code) == []
    end
  end

  # ── fix ────────────────────────────────────────────────────────

  describe "fix" do
    test "sort with ascending comparator → sort_by" do
      result = fix("Enum.sort(list, fn {_, _, w1}, {_, _, w2} -> w1 < w2 end)")
      assert result =~ "Enum.sort_by(list, &elem(&1, 2))"
      refute result =~ "Enum.sort("
    end

    test "sort with descending comparator → sort_by with :desc" do
      result = fix("Enum.sort(list, fn {a, _}, {b, _} -> a > b end)")
      assert result =~ "Enum.sort_by(list, &elem(&1, 0), :desc)"
    end

    test "sort with <= comparator → sort_by ascending" do
      result = fix("Enum.sort(list, fn {_, a}, {_, b} -> a <= b end)")
      assert result =~ "Enum.sort_by(list, &elem(&1, 1))"
      refute result =~ ":desc"
    end

    test "sort in pipe → sort_by in pipe" do
      result = fix("list |> Enum.sort(fn {_, _, w1}, {_, _, w2} -> w1 < w2 end)")
      assert result =~ "|> Enum.sort_by(&elem(&1, 2))"
      refute result =~ "Enum.sort("
    end

    test "sort with 2-tuple → sort_by" do
      result = fix("Enum.sort(list, fn {k, _}, {k2, _} -> k < k2 end)")
      assert result =~ "Enum.sort_by(list, &elem(&1, 0))"
    end

    test "sort in function body" do
      source = """
      defmodule Example do
        def f(list), do: Enum.sort(list, fn {_, _, w1}, {_, _, w2} -> w1 < w2 end)
      end
      """

      result = fix(source)
      assert result =~ "Enum.sort_by(list, &elem(&1, 2))"
      refute result =~ "Enum.sort("
    end

    test "does not change non-matching code" do
      code = "Enum.sort(list, fn a, b -> a < b end)"
      assert fix(code) == code
    end

    test "does not change multi-var tuple comparator" do
      code = "Enum.sort(list, fn {a, b}, {c, d} -> a < c end)"
      assert fix(code) == code
    end
  end
end
