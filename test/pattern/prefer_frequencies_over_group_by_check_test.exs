defmodule Credence.Pattern.PreferFrequenciesOverGroupByCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferFrequenciesOverGroupBy

  describe "flags the anti-pattern" do
    test "identity group_by |> map(length) |> count(> 1)" do
      code = """
      defmodule M do
        def count_dupes(input) do
          input
          |> String.downcase()
          |> String.graphemes()
          |> Enum.group_by(fn char -> char end)
          |> Enum.map(fn {_key, values} -> length(values) end)
          |> Enum.count(fn count -> count > 1 end)
        end
      end
      """

      issues = check(PreferFrequenciesOverGroupBy, code)
      assert length(issues) == 1
      assert hd(issues).rule == :prefer_frequencies_over_group_by
      assert hd(issues).message =~ "Enum.frequencies"
    end

    test "identity group_by with single-letter var" do
      code = """
      def dupes(list) do
        list
        |> Enum.group_by(fn x -> x end)
        |> Enum.map(fn {_, v} -> length(v) end)
        |> Enum.count(fn c -> c > 1 end)
      end
      """

      assert length(check(PreferFrequenciesOverGroupBy, code)) == 1
    end

    test "capture-form identity group_by" do
      code = """
      def dupes(list) do
        list
        |> Enum.group_by(& &1)
        |> Enum.map(fn {_, v} -> length(v) end)
        |> Enum.count(fn c -> c > 1 end)
      end
      """

      assert length(check(PreferFrequenciesOverGroupBy, code)) == 1
    end

    test "extra steps before the pattern" do
      code = """
      def dupes(input) do
        input
        |> String.downcase()
        |> String.graphemes()
        |> Enum.group_by(fn char -> char end)
        |> Enum.map(fn {_key, values} -> length(values) end)
        |> Enum.count(fn count -> count > 1 end)
      end
      """

      assert length(check(PreferFrequenciesOverGroupBy, code)) == 1
    end
  end

  describe "does not flag — out of scope" do
    test "non-identity group_by" do
      code = """
      def dupes(list) do
        list
        |> Enum.group_by(fn x -> x.key end)
        |> Enum.map(fn {_, v} -> length(v) end)
        |> Enum.count(fn c -> c > 1 end)
      end
      """

      assert check(PreferFrequenciesOverGroupBy, code) == []
    end

    test "group_by |> map with non-length transform" do
      code = """
      def dupes(list) do
        list
        |> Enum.group_by(fn x -> x end)
        |> Enum.map(fn {k, v} -> {k, hd(v)} end)
        |> Enum.count(fn c -> c > 1 end)
      end
      """

      assert check(PreferFrequenciesOverGroupBy, code) == []
    end

    test "count with predicate other than > 1" do
      code = """
      def dupes(list) do
        list
        |> Enum.group_by(fn x -> x end)
        |> Enum.map(fn {_, v} -> length(v) end)
        |> Enum.count(fn c -> c > 2 end)
      end
      """

      assert check(PreferFrequenciesOverGroupBy, code) == []
    end

    test "group_by alone without map and count" do
      code = """
      def grouped(list) do
        Enum.group_by(list, fn x -> x end)
      end
      """

      assert check(PreferFrequenciesOverGroupBy, code) == []
    end

    test "Enum.frequencies already used" do
      code = """
      def dupes(list) do
        list
        |> Enum.frequencies()
        |> Enum.count(fn {_, c} -> c > 1 end)
      end
      """

      assert check(PreferFrequenciesOverGroupBy, code) == []
    end
  end
end
