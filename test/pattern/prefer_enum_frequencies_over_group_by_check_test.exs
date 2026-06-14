defmodule Credence.Pattern.PreferEnumFrequenciesOverGroupByCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferEnumFrequenciesOverGroupBy

  describe "flags the anti-pattern" do
    test "head-position pipe: Enum.group_by(enum, & &1) |> Map.new(...)" do
      code = "Enum.group_by(list, & &1) |> Map.new(fn {k, v} -> {k, length(v)} end)"

      issues = check(PreferEnumFrequenciesOverGroupBy, code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_enum_frequencies_over_group_by
    end

    test "piped form: list |> Enum.group_by(& &1) |> Map.new(...)" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      assert flagged?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "direct form: Map.new(Enum.group_by(enum, & &1), fn ...)" do
      code = "Map.new(Enum.group_by(list, & &1), fn {k, v} -> {k, length(v)} end)"

      assert flagged?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "fn x -> x end identity variant" do
      code = """
      list
      |> Enum.group_by(fn x -> x end)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      assert flagged?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "Enum.count variant" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, g} -> {k, Enum.count(g)} end)
      """

      assert flagged?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "Kernel.length variant" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, g} -> {k, Kernel.length(g)} end)
      """

      assert flagged?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "inside a module" do
      code = """
      defmodule FrequencyExample do
        def count_items(list) do
          Enum.group_by(list, & &1) |> Map.new(fn {k, v} -> {k, length(v)} end)
        end
      end
      """

      assert flagged?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "piped Enum.into(%{}) collector" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Enum.into(%{}, fn {k, v} -> {k, length(v)} end)
      """

      assert flagged?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "direct Enum.into(group_by, %{}, ...) collector" do
      code = "Enum.into(Enum.group_by(list, & &1), %{}, fn {k, v} -> {k, length(v)} end)"

      assert flagged?(PreferEnumFrequenciesOverGroupBy, code)
    end
  end

  describe "does not flag — out of scope" do
    test "Enum.frequencies/1 (already idiomatic)" do
      code = "Enum.frequencies(list)"

      assert clean?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "Enum.frequencies_by/2 (non-identity key function)" do
      code = "Enum.frequencies_by(words, &String.downcase/1)"

      assert clean?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "non-identity key function" do
      code = """
      list
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      assert clean?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "group_by alone, without Map.new" do
      code = "Enum.group_by(list, & &1)"

      assert clean?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "Map.new alone, without group_by" do
      code = "Map.new(list, fn x -> {x, x} end)"

      assert clean?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "non-length transform" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, items} -> {k, hd(items)} end)
      """

      assert clean?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "arithmetic on length" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, g} -> {k, length(g) + 1} end)
      """

      assert clean?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "second argument capture & &2" do
      code = """
      list
      |> Enum.group_by(& &2)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      assert clean?(PreferEnumFrequenciesOverGroupBy, code)
    end

    test "Enum.into into a non-map target (would produce a list, not a map)" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Enum.into([], fn {k, v} -> {k, length(v)} end)
      """

      assert clean?(PreferEnumFrequenciesOverGroupBy, code)
    end
  end
end
