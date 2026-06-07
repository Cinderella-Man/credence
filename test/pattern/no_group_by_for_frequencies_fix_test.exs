defmodule Credence.Pattern.NoGroupByForFrequenciesFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoGroupByForFrequencies

  describe "rewrites to Enum.frequencies_by/2" do
    test "piped group_by/2 |> Map.new(length)" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      expected = """
      Enum.frequencies_by(words, &String.downcase/1)
      """

      assert fix(NoGroupByForFrequencies, code) == expected
    end

    test "direct Map.new(Enum.group_by/2, ...)" do
      code = """
      Map.new(Enum.group_by(words, &String.downcase/1), fn {key, group} -> {key, length(group)} end)
      """

      expected = """
      Enum.frequencies_by(words, &String.downcase/1)
      """

      assert fix(NoGroupByForFrequencies, code) == expected
    end

    test "Enum.count variant" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Map.new(fn {k, g} -> {k, Enum.count(g)} end)
      """

      expected = """
      Enum.frequencies_by(list, & &1)
      """

      assert fix(NoGroupByForFrequencies, code) == expected
    end

    test "Kernel.length variant" do
      code = """
      list
      |> Enum.group_by(fn x -> x end)
      |> Map.new(fn {key, group} -> {key, Kernel.length(group)} end)
      """

      expected = """
      Enum.frequencies_by(list, fn x -> x end)
      """

      assert fix(NoGroupByForFrequencies, code) == expected
    end

    test "preserves leading pipe steps as the enum source" do
      code = """
      data
      |> Enum.map(fn x -> x.name end)
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      expected = """
      Enum.frequencies_by(data |> Enum.map(fn x -> x.name end), &String.downcase/1)
      """

      assert fix(NoGroupByForFrequencies, code) == expected
    end

    test "preserves a trailing pipe step after Map.new" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      |> Enum.sort()
      """

      expected = """
      Enum.frequencies_by(words, &String.downcase/1)
      |> Enum.sort()
      """

      assert fix(NoGroupByForFrequencies, code) == expected
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def freq(words) do
          total = length(words)

          counts =
            words
            |> Enum.group_by(&String.downcase/1)
            |> Map.new(fn {key, group} -> {key, length(group)} end)

          {total, counts}
        end
      end
      """

      expected = """
      defmodule M do
        def freq(words) do
          total = length(words)

          counts =
            Enum.frequencies_by(words, &String.downcase/1)

          {total, counts}
        end
      end
      """

      assert fix(NoGroupByForFrequencies, code) == expected
    end
  end

  describe "no-op — leaves code unchanged" do
    test "non-frequency group_by (different transform)" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, items} -> {key, hd(items)} end)
      """

      assert fix(NoGroupByForFrequencies, code) == code
    end

    test "piped group_by/3 with a value_fun" do
      code = """
      list
      |> Enum.group_by(fn x -> x.key end, fn x -> x.value end)
      |> Map.new(fn {k, g} -> {k, length(g)} end)
      """

      assert fix(NoGroupByForFrequencies, code) == code
    end

    test "head-position group_by in a pipe" do
      code = """
      Enum.group_by(words, &String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      assert fix(NoGroupByForFrequencies, code) == code
    end
  end

  describe "round-trip" do
    test "fixed code no longer triggers the rule" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      fixed = fix(NoGroupByForFrequencies, code)
      assert clean?(NoGroupByForFrequencies, fixed)
    end
  end
end
