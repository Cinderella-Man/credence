defmodule Credence.Pattern.PreferEnumFrequenciesFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferEnumFrequencies

  describe "rewrites to Enum.frequencies/1" do
    test "full pipeline with Enum.count" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      |> Enum.take(k)
      |> Enum.map(&elem(&1, 0))
      """

      expected = """
      Enum.frequencies(nums)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      |> Enum.take(k)
      |> Enum.map(&elem(&1, 0))
      """

      confirm_fix(fix(PreferEnumFrequencies, code), expected)
    end

    test "with length/1" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, length(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      expected = """
      Enum.frequencies(nums)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      confirm_fix(fix(PreferEnumFrequencies, code), expected)
    end

    test "with capture identity" do
      code = """
      nums
      |> Enum.group_by(& &1, & &1)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      expected = """
      Enum.frequencies(nums)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      confirm_fix(fix(PreferEnumFrequencies, code), expected)
    end

    test "inside a module" do
      code = """
      defmodule Solution do
        def k_frequent(nums, k) do
          nums
          |> Enum.group_by(fn x -> x end, fn x -> x end)
          |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
          |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
          |> Enum.take(k)
          |> Enum.map(&elem(&1, 0))
        end
      end
      """

      expected = """
      defmodule Solution do
        def k_frequent(nums, k) do
          Enum.frequencies(nums)
          |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
          |> Enum.take(k)
          |> Enum.map(&elem(&1, 0))
        end
      end
      """

      confirm_fix(fix(PreferEnumFrequencies, code), expected)
    end

    test "preserves preceding pipeline steps" do
      code = """
      data
      |> Enum.filter(fn x -> x > 0 end)
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      expected = """
      Enum.frequencies(data |> Enum.filter(fn x -> x > 0 end))
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      confirm_fix(fix(PreferEnumFrequencies, code), expected)
    end
  end

  describe "no-op — leaves code unchanged" do
    test "standalone without downstream steps (type change)" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      """

      confirm_fix(fix(PreferEnumFrequencies, code), code)
    end

    test "Enum.frequencies (already correct)" do
      code = "Enum.frequencies(nums)"

      confirm_fix(fix(PreferEnumFrequencies, code), code)
    end

    test "group_by with non-identity key function" do
      code = """
      nums
      |> Enum.group_by(fn x -> rem(x, 2) end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      confirm_fix(fix(PreferEnumFrequencies, code), code)
    end

    test "group_by with non-identity value function" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x * 2 end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      confirm_fix(fix(PreferEnumFrequencies, code), code)
    end

    test "non-count map callback" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, hd(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      confirm_fix(fix(PreferEnumFrequencies, code), code)
    end
  end

  describe "round-trip" do
    test "fixed code no longer triggers the rule" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      fixed = fix(PreferEnumFrequencies, code)
      assert clean?(PreferEnumFrequencies, fixed)
    end
  end
end
