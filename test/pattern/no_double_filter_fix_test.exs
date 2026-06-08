defmodule Credence.Pattern.NoDoubleFilterFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoDoubleFilter

  describe "rewrites adjacent complementary filters to split_with" do
    test "ge / lt" do
      code = """
      def split(numbers) do
        non_neg = Enum.filter(numbers, &(&1 >= 0))
        neg = Enum.filter(numbers, &(&1 < 0))
        {non_neg, neg}
      end
      """

      expected = """
      def split(numbers) do
        {non_neg, neg} = Enum.split_with(numbers, &(&1 >= 0))
        {non_neg, neg}
      end
      """

      assert fix(NoDoubleFilter, code) == expected
    end

    test "eq / neq" do
      code = """
      def split(items) do
        zeros = Enum.filter(items, &(&1 == 0))
        nonzeros = Enum.filter(items, &(&1 != 0))
        {zeros, nonzeros}
      end
      """

      expected = """
      def split(items) do
        {zeros, nonzeros} = Enum.split_with(items, &(&1 == 0))
        {zeros, nonzeros}
      end
      """

      assert fix(NoDoubleFilter, code) == expected
    end

    test "operand is a bound variable" do
      code = """
      def split(items, threshold) do
        keep = Enum.filter(items, &(&1 >= threshold))
        drop = Enum.filter(items, &(&1 < threshold))
        {keep, drop}
      end
      """

      expected = """
      def split(items, threshold) do
        {keep, drop} = Enum.split_with(items, &(&1 >= threshold))
        {keep, drop}
      end
      """

      assert fix(NoDoubleFilter, code) == expected
    end
  end

  describe "leaves out-of-core shapes unchanged" do
    test "non-complementary gt / lt is a no-op" do
      code = """
      def split(list) do
        pos = Enum.filter(list, &(&1 > 0))
        neg = Enum.filter(list, &(&1 < 0))
        {pos, neg}
      end
      """

      assert fix(NoDoubleFilter, code) == code
    end

    test "non-adjacent filters is a no-op" do
      code = """
      def split(numbers) do
        non_neg = Enum.filter(numbers, &(&1 >= 0))
        log(non_neg)
        neg = Enum.filter(numbers, &(&1 < 0))
        {non_neg, neg}
      end
      """

      assert fix(NoDoubleFilter, code) == code
    end

    test "single filter is a no-op" do
      code = """
      def positives(numbers) do
        result = Enum.filter(numbers, &(&1 >= 0))
        result
      end
      """

      assert fix(NoDoubleFilter, code) == code
    end
  end
end
