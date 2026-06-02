defmodule Credence.Pattern.NoGroupByForFrequenciesTest do
  use ExUnit.Case

  alias Credence.Pattern.NoGroupByForFrequencies

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoGroupByForFrequencies.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoGroupByForFrequencies, code, [])

  describe "check" do
    test "detects piped group_by |> Map.new with length" do
      code = """
      defmodule M do
        def freq(words) do
          words
          |> Enum.group_by(&String.downcase/1)
          |> Map.new(fn {key, group} -> {key, length(group)} end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_group_by_for_frequencies
      assert hd(issues).message =~ "Enum.frequencies_by"
    end

    test "detects direct Map.new(Enum.group_by(...)) form" do
      code = """
      defmodule M do
        def freq(words) do
          Map.new(Enum.group_by(words, &String.downcase/1), fn {key, group} -> {key, length(group)} end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_group_by_for_frequencies
    end

    test "detects Enum.count variant" do
      code = """
      defmodule M do
        def freq(list) do
          list
          |> Enum.group_by(& &1)
          |> Map.new(fn {k, g} -> {k, Enum.count(g)} end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects Kernel.length remote call variant" do
      code = """
      defmodule M do
        def freq(list) do
          list
          |> Enum.group_by(fn x -> x end)
          |> Map.new(fn {key, group} -> {key, Kernel.length(group)} end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does not flag group_by |> Map.new with non-length transform" do
      code = """
      defmodule M do
        def first_by_key(list) do
          list
          |> Enum.group_by(fn x -> x.key end)
          |> Map.new(fn {k, items} -> {k, hd(items)} end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag group_by |> Map.new with arithmetic on length" do
      code = """
      defmodule M do
        def adjusted(list) do
          list
          |> Enum.group_by(& &1)
          |> Map.new(fn {k, g} -> {k, length(g) + 1} end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Map.new on non-group_by source" do
      code = """
      defmodule M do
        def to_map(list) do
          Map.new(list, fn x -> {x.key, x.value} end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag group_by alone without Map.new" do
      code = """
      defmodule M do
        def grouped(list) do
          Enum.group_by(list, &String.downcase/1)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces piped group_by |> Map.new with Enum.frequencies_by" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      result = fix(code)
      assert result =~ "Enum.frequencies_by"
      assert result =~ "String.downcase"
      refute result =~ "Enum.group_by"
      refute result =~ "Map.new"
    end

    test "replaces direct Map.new(Enum.group_by(...)) form" do
      code = """
      Map.new(Enum.group_by(words, &String.downcase/1), fn {key, group} -> {key, length(group)} end)
      """

      result = fix(code)
      assert result =~ "Enum.frequencies_by"
      assert result =~ "words"
      refute result =~ "Enum.group_by"
      refute result =~ "Map.new"
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

      result = fix(code)
      assert result =~ "total = length(words)"
      assert result =~ "Enum.frequencies_by"
      assert result =~ "{total, counts}"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, group} -> {key, length(group)} end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoGroupByForFrequencies.check(ast, []) == []
    end

    test "does not modify non-frequency group_by" do
      code = """
      words
      |> Enum.group_by(&String.downcase/1)
      |> Map.new(fn {key, items} -> {key, hd(items)} end)
      """

      result = fix(code)
      assert result =~ "Enum.group_by"
      assert result =~ "Map.new"
    end
  end
end
