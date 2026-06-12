defmodule Credence.Pattern.PreferEnumFrequenciesOverGroupByFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferEnumFrequenciesOverGroupBy

  describe "rewrites to Enum.frequencies/1" do
    test "head-position pipe: Enum.group_by(enum, & &1) |> Map.new(...)" do
      code = """
      Enum.group_by(list, & &1) |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      expected = """
      Enum.frequencies(list)
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == expected
    end

    test "piped form: list |> Enum.group_by(& &1) |> Map.new(...)" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      expected = """
      Enum.frequencies(list)
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == expected
    end

    test "direct form: Map.new(Enum.group_by(enum, & &1), fn ...)" do
      code = """
      Map.new(Enum.group_by(list, & &1), fn {k, v} -> {k, length(v)} end)
      """

      expected = """
      Enum.frequencies(list)
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == expected
    end

    test "fn x -> x end identity variant" do
      code = """
      list
      |> Enum.group_by(fn x -> x end)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      expected = """
      Enum.frequencies(list)
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == expected
    end

    test "preserves surrounding code" do
      code = """
      defmodule FrequencyExample do
        def count_items(list) do
          Enum.group_by(list, & &1) |> Map.new(fn {k, v} -> {k, length(v)} end)
        end
      end
      """

      expected = """
      defmodule FrequencyExample do
        def count_items(list) do
          Enum.frequencies(list)
        end
      end
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == expected
    end

    test "piped Enum.into(%{}) collector: list |> Enum.group_by(& &1) |> Enum.into(%{}, ...)" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Enum.into(%{}, fn {k, v} -> {k, length(v)} end)
      """

      expected = """
      Enum.frequencies(list)
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == expected
    end

    test "direct Enum.into form: Enum.into(Enum.group_by(enum, & &1), %{}, fn ...)" do
      code = """
      Enum.into(Enum.group_by(list, & &1), %{}, fn {k, v} -> {k, length(v)} end)
      """

      expected = """
      Enum.frequencies(list)
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == expected
    end

    test "preserves leading pipe steps as the enum source" do
      code = """
      data
      |> Enum.map(fn x -> x.name end)
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      expected = """
      Enum.frequencies(data |> Enum.map(fn x -> x.name end))
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == expected
    end
  end

  describe "no-op — leaves code unchanged" do
    test "non-identity key function" do
      code = """
      list
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == code
    end

    test "non-frequency transform" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, items} -> {k, hd(items)} end)
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == code
    end

    test "Enum.frequencies (already correct)" do
      code = """
      Enum.frequencies(list)
      """

      assert fix(PreferEnumFrequenciesOverGroupBy, code) == code
    end
  end

  describe "round-trip" do
    test "fixed code no longer triggers the rule" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
      """

      fixed = fix(PreferEnumFrequenciesOverGroupBy, code)
      assert clean?(PreferEnumFrequenciesOverGroupBy, fixed)
    end
  end
end
