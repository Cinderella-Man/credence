defmodule Credence.Pattern.PreferEnumCountFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferEnumCount

  describe "fix" do
    test "rewrites piped counting reduce to Enum.count/2" do
      input = """
      values
      |> Enum.reduce(0, fn count, odd_count ->
        if rem(count, 2) == 1, do: odd_count + 1, else: odd_count
      end)
      """

      expected = """
      values
      |> Enum.count(&(rem(&1, 2) == 1))
      """

      confirm_fix(fix(PreferEnumCount, input), expected)
    end

    test "rewrites non-piped counting reduce to Enum.count/2" do
      input = """
      Enum.reduce(list, 0, fn x, acc ->
        if x > 5, do: acc + 1, else: acc
      end)
      """

      expected = "Enum.count(list, &(&1 > 5))"

      confirm_fix(fix(PreferEnumCount, input), expected)
    end

    test "handles reversed operand order (1 + acc)" do
      input = """
      Enum.reduce(list, 0, fn x, acc ->
        if rem(x, 3) == 0, do: 1 + acc, else: acc
      end)
      """

      expected = "Enum.count(list, &(rem(&1, 3) == 0))"

      confirm_fix(fix(PreferEnumCount, input), expected)
    end

    test "does not modify non-counting reductions" do
      code = "Enum.reduce(list, 0, fn x, acc -> acc + x end)"

      confirm_fix(fix(PreferEnumCount, code), code)
    end

    test "does not modify reduce with non-zero initial accumulator" do
      code = """
      Enum.reduce(list, 1, fn x, acc ->
        if x > 0, do: acc + 1, else: acc
      end)
      """

      confirm_fix(fix(PreferEnumCount, code), code)
    end

    test "preserves surrounding code" do
      input = """
      defmodule M do
        def count_odds(values) do
          values
          |> Enum.reduce(0, fn count, odd_count ->
            if rem(count, 2) == 1, do: odd_count + 1, else: odd_count
          end)
        end
      end
      """

      expected = """
      defmodule M do
        def count_odds(values) do
          values
          |> Enum.count(&(rem(&1, 2) == 1))
        end
      end
      """

      confirm_fix(fix(PreferEnumCount, input), expected)
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if x > 5, do: acc + 1, else: acc
      end)
      """

      assert check(PreferEnumCount, fix(PreferEnumCount, code)) == []
    end
  end
end
