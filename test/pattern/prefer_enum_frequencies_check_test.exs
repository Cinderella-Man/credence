defmodule Credence.Pattern.PreferEnumFrequenciesCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferEnumFrequencies

  describe "flags the anti-pattern" do
    test "full pipeline with downstream steps" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      |> Enum.take(k)
      |> Enum.map(&elem(&1, 0))
      """

      assert flagged?(PreferEnumFrequencies, code)
    end

    test "with one downstream step" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert flagged?(PreferEnumFrequencies, code)
    end

    test "with length/1 instead of Enum.count/1" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, length(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert flagged?(PreferEnumFrequencies, code)
    end

    test "with Kernel.length/1" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {k, g} -> {k, Kernel.length(g)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert flagged?(PreferEnumFrequencies, code)
    end

    test "with capture identity & &1" do
      code = """
      nums
      |> Enum.group_by(& &1, & &1)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert flagged?(PreferEnumFrequencies, code)
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

      assert flagged?(PreferEnumFrequencies, code)
    end

    test "direct form: Enum.map(Enum.group_by(enum, k, v), callback)" do
      code = """
      Enum.map(Enum.group_by(nums, fn x -> x end, fn x -> x end), fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert flagged?(PreferEnumFrequencies, code)
    end
  end

  describe "does not flag — out of scope" do
    test "Enum.frequencies/1 (already idiomatic)" do
      code = """
      Enum.frequencies(nums)
      """

      assert clean?(PreferEnumFrequencies, code)
    end

    test "Enum.frequencies() in a pipe" do
      code = """
      nums
      |> Enum.frequencies()
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert clean?(PreferEnumFrequencies, code)
    end

    test "standalone group_by |> map(count) without downstream steps" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      """

      assert clean?(PreferEnumFrequencies, code)
    end

    test "group_by with single identity (no value function)" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      assert clean?(PreferEnumFrequencies, code)
    end

    test "group_by with non-identity key function" do
      code = """
      nums
      |> Enum.group_by(fn x -> rem(x, 2) end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert clean?(PreferEnumFrequencies, code)
    end

    test "group_by with non-identity value function" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x * 2 end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert clean?(PreferEnumFrequencies, code)
    end

    test "map callback does not count" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, hd(vals)} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert clean?(PreferEnumFrequencies, code)
    end

    test "map callback does arithmetic on count" do
      code = """
      nums
      |> Enum.group_by(fn x -> x end, fn x -> x end)
      |> Enum.map(fn {val, vals} -> {val, Enum.count(vals) + 1} end)
      |> Enum.sort(fn {_, freq_a}, {_, freq_b} -> freq_a > freq_b end)
      """

      assert clean?(PreferEnumFrequencies, code)
    end
  end
end
