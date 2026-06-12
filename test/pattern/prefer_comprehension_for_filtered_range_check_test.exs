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
  end

  describe "leaves good code alone" do
    test "already a for comprehension" do
      code = """
      for num <- 1..n, !MapSet.member?(present, num), do: num
      """

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
  end
end
