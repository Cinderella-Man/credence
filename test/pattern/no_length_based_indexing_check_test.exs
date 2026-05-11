defmodule Credence.Pattern.NoLengthBasedIndexingCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoLengthBasedIndexing.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags length + Enum.at(var, n - K)" do
    test "basic single usage" do
      assert flagged?("""
             def run(list) do
               n = length(list)
               last = Enum.at(list, n - 1)
               last
             end
             """)
    end

    test "multiple Enum.at with length-based indices" do
      assert flagged?("""
             def run(sorted) do
               n = length(sorted)
               largest = Enum.at(sorted, n - 1)
               second = Enum.at(sorted, n - 2)
               third = Enum.at(sorted, n - 3)
               {largest, second, third}
             end
             """)
    end

    test "Enum.count variant" do
      assert flagged?("""
             def run(list) do
               n = Enum.count(list)
               last = Enum.at(list, n - 1)
               last
             end
             """)
    end

    test "inside a module" do
      assert flagged?("""
             defmodule Example do
               def run(sorted) do
                 n = length(sorted)
                 last = Enum.at(sorted, n - 1)
                 last
               end
             end
             """)
    end

    test "different variable name for length" do
      assert flagged?("""
             def run(list) do
               count = length(list)
               last = Enum.at(list, count - 1)
               last
             end
             """)
    end

    test "length used for indexing AND other purposes" do
      assert flagged?("""
             def run(numbers) do
               n = length(numbers)
               expected = div(n * (n + 1), 2)
               last = Enum.at(numbers, n - 1)
               {expected, last}
             end
             """)
    end

    test "mixed literal and length-based indices" do
      assert flagged?("""
             def run(sorted) do
               n = length(sorted)
               first = Enum.at(sorted, 0)
               last = Enum.at(sorted, n - 1)
               {first, last}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag negative indices" do
    test "already using negative indices" do
      assert clean?("""
             def run(list) do
               last = Enum.at(list, -1)
               second = Enum.at(list, -2)
               {last, second}
             end
             """)
    end
  end

  describe "does not flag length used only for non-indexing" do
    test "length used in arithmetic only" do
      assert clean?("""
             def run(numbers) do
               n = length(numbers)
               expected = div(n * (n + 1), 2)
               actual = Enum.sum(numbers)
               expected - actual
             end
             """)
    end

    test "length used in guard or condition" do
      assert clean?("""
             def run(list) do
               n = length(list)
               if n > 0, do: :non_empty, else: :empty
             end
             """)
    end
  end

  describe "does not flag different list variables" do
    test "length on one var, Enum.at on another" do
      assert clean?("""
             def run(a, b) do
               n = length(a)
               last = Enum.at(b, n - 1)
               last
             end
             """)
    end
  end

  describe "does not flag non-literal subtraction" do
    test "variable offset" do
      assert clean?("""
             def run(list, offset) do
               n = length(list)
               val = Enum.at(list, n - offset)
               val
             end
             """)
    end
  end

  describe "does not flag non-subtraction index expressions" do
    test "addition: n + 1" do
      assert clean?("""
             def run(list) do
               n = length(list)
               val = Enum.at(list, n + 1)
               val
             end
             """)
    end

    test "multiplication: n * 2" do
      assert clean?("""
             def run(list) do
               n = length(list)
               val = Enum.at(list, n * 2)
               val
             end
             """)
    end

    test "bare n without subtraction" do
      assert clean?("""
             def run(list) do
               n = length(list)
               val = Enum.at(list, n)
               val
             end
             """)
    end
  end

  describe "does not flag when no length binding exists" do
    test "Enum.at with literal index only" do
      assert clean?("""
             def run(list) do
               first = Enum.at(list, 0)
               second = Enum.at(list, 1)
               {first, second}
             end
             """)
    end
  end

  describe "does not flag variable rebound between length and Enum.at" do
    test "list rebound" do
      assert clean?("""
             def run(list) do
               n = length(list)
               list = Enum.filter(list, &(&1 > 0))
               last = Enum.at(list, n - 1)
               last
             end
             """)
    end

    test "length variable rebound" do
      assert clean?("""
             def run(list) do
               n = length(list)
               n = n + 1
               last = Enum.at(list, n - 1)
               last
             end
             """)
    end
  end

  describe "does not flag different scopes" do
    test "length and Enum.at in different functions" do
      assert clean?("""
             defmodule M do
               def get_length(list), do: length(list)
               def get_last(list, n), do: Enum.at(list, n - 1)
             end
             """)
    end
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoLengthBasedIndexing.fixable?() == true
    end
  end
end
