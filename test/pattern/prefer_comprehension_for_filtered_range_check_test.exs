defmodule Credence.Pattern.PreferComprehensionForFilteredRangeCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferComprehensionForFilteredRange

  describe "flags the anti-pattern" do
    test "piped Enum.reduce |> Enum.reverse over a range with MapSet filter" do
      code = """
      defmodule Bad do
        def findmissingnumbers(numbers) do
          n = length(numbers)
          present = MapSet.new(numbers)

          Enum.reduce(1..n, [], fn num, missing ->
            if MapSet.member?(present, num), do: missing, else: [num | missing]
          end)
          |> Enum.reverse()
        end
      end
      """

      assert flagged?(PreferComprehensionForFilteredRange, code)
    end

    test "direct Enum.reverse(Enum.reduce(...)) form" do
      code = """
      Enum.reverse(Enum.reduce(1..n, [], fn num, acc ->
        if MapSet.member?(set, num), do: acc, else: [num | acc]
      end))
      """

      assert flagged?(PreferComprehensionForFilteredRange, code)
    end

    test "literal range" do
      code = """
      Enum.reduce(1..10, [], fn i, acc ->
        if MapSet.member?(s, i), do: acc, else: [i | acc]
      end)
      |> Enum.reverse()
      """

      assert flagged?(PreferComprehensionForFilteredRange, code)
    end

    test "explicit-step range (1..n//1)" do
      code = """
      Enum.reduce(1..n//1, [], fn num, acc ->
        if MapSet.member?(s, num), do: acc, else: [num | acc]
      end)
      |> Enum.reverse()
      """

      assert flagged?(PreferComprehensionForFilteredRange, code)
    end
  end

  describe "leaves good code alone" do
    test "Enum alias shadowed by another module" do
      code = """
      defmodule PreferComprehensionAliasProbe do
        alias MyEnum, as: Enum

        def run(n) do
          Enum.reduce(1..n, [], fn num, acc ->
            if rem(num, 2) == 0, do: acc, else: [num | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      assert clean?(PreferComprehensionForFilteredRange, code)
    end

    test "already a for comprehension" do
      code = "for num <- 1..n, !MapSet.member?(present, num), do: num"

      assert clean?(PreferComprehensionForFilteredRange, code)
    end

    test "Enum.reduce without Enum.reverse" do
      code = """
      Enum.reduce(1..n, [], fn num, acc ->
        if MapSet.member?(s, num), do: acc, else: [num | acc]
      end)
      """

      assert clean?(PreferComprehensionForFilteredRange, code)
    end

    test "reduce with non-empty initial accumulator" do
      code = """
      Enum.reduce(1..n, [0], fn num, acc ->
        if MapSet.member?(s, num), do: acc, else: [num | acc]
      end)
      |> Enum.reverse()
      """

      assert clean?(PreferComprehensionForFilteredRange, code)
    end

    test "reduce over a non-range enumerable" do
      code = """
      Enum.reduce(list, [], fn num, acc ->
        if MapSet.member?(s, num), do: acc, else: [num | acc]
      end)
      |> Enum.reverse()
      """

      assert clean?(PreferComprehensionForFilteredRange, code)
    end

    test "reduce with different body structure" do
      code = """
      Enum.reduce(1..n, [], fn num, acc ->
        [num * 2 | acc]
      end)
      |> Enum.reverse()
      """

      assert clean?(PreferComprehensionForFilteredRange, code)
    end

    # The rewrite always yields the loop element (first param). A body that
    # prepends some OTHER variable produces a different list, so it must not
    # be flagged. (Reduce here builds `[other, other, ...]`, not the elements.)
    test "else prepends a variable other than the loop element" do
      code = """
      Enum.reduce(1..n, [], fn num, acc ->
        if MapSet.member?(s, num), do: acc, else: [other | acc]
      end)
      |> Enum.reverse()
      """

      assert clean?(PreferComprehensionForFilteredRange, code)
    end

    # The do-branch must return the accumulator unchanged; returning some other
    # value changes the result, so it must not be flagged.
    test "do-branch returns a value other than the accumulator" do
      code = """
      Enum.reduce(1..n, [], fn num, acc ->
        if MapSet.member?(s, num), do: other, else: [num | acc]
      end)
      |> Enum.reverse()
      """

      assert clean?(PreferComprehensionForFilteredRange, code)
    end

    # The comprehension has no accumulator binding, so a condition that reads
    # the accumulator (`length(acc)`) cannot carry through — must not be flagged.
    test "condition references the accumulator" do
      code = """
      Enum.reduce(1..n, [], fn num, acc ->
        if length(acc) >= 2, do: acc, else: [num | acc]
      end)
      |> Enum.reverse()
      """

      assert clean?(PreferComprehensionForFilteredRange, code)
    end
  end
end
