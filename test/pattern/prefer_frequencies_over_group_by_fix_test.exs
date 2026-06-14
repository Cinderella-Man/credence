defmodule Credence.Pattern.PreferFrequenciesOverGroupByFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferFrequenciesOverGroupBy

  describe "rewrites to Enum.frequencies()" do
    test "identity group_by |> map(length) |> count(> 1)" do
      code = """
      input
      |> String.downcase()
      |> String.graphemes()
      |> Enum.group_by(fn char -> char end)
      |> Enum.map(fn {_key, values} -> length(values) end)
      |> Enum.count(fn count -> count > 1 end)
      """

      expected = """
      input
      |> String.downcase()
      |> String.graphemes()
      |> Enum.frequencies()
      |> Enum.count(fn {_char, count} -> count > 1 end)
      """

      confirm_fix(fix(PreferFrequenciesOverGroupBy, code), expected)
    end

    test "capture-form identity group_by" do
      code = """
      list
      |> Enum.group_by(& &1)
      |> Enum.map(fn {_, v} -> length(v) end)
      |> Enum.count(fn c -> c > 1 end)
      """

      expected = """
      list
      |> Enum.frequencies()
      |> Enum.count(fn {_char, count} -> count > 1 end)
      """

      confirm_fix(fix(PreferFrequenciesOverGroupBy, code), expected)
    end

    test "preserves surrounding code" do
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

      expected = """
      defmodule M do
        def count_dupes(input) do
          input
          |> String.downcase()
          |> String.graphemes()
          |> Enum.frequencies()
          |> Enum.count(fn {_char, count} -> count > 1 end)
        end
      end
      """

      confirm_fix(fix(PreferFrequenciesOverGroupBy, code), expected)
    end

    test "round-trip: fixed code no longer triggers the rule" do
      code = """
      input
      |> String.graphemes()
      |> Enum.group_by(fn char -> char end)
      |> Enum.map(fn {_key, values} -> length(values) end)
      |> Enum.count(fn count -> count > 1 end)
      """

      fixed = fix(PreferFrequenciesOverGroupBy, code)
      assert clean?(PreferFrequenciesOverGroupBy, fixed)
    end
  end

  describe "no-op — leaves code unchanged" do
    test "non-identity group_by" do
      code = """
      list
      |> Enum.group_by(fn x -> x.key end)
      |> Enum.map(fn {_, v} -> length(v) end)
      |> Enum.count(fn c -> c > 1 end)
      """

      confirm_fix(fix(PreferFrequenciesOverGroupBy, code), code)
    end

    test "group_by |> map with non-length transform" do
      code = """
      list
      |> Enum.group_by(fn x -> x end)
      |> Enum.map(fn {k, v} -> {k, hd(v)} end)
      |> Enum.count(fn c -> c > 1 end)
      """

      confirm_fix(fix(PreferFrequenciesOverGroupBy, code), code)
    end

    test "count with predicate other than > 1" do
      code = """
      list
      |> Enum.group_by(fn x -> x end)
      |> Enum.map(fn {_, v} -> length(v) end)
      |> Enum.count(fn c -> c > 2 end)
      """

      confirm_fix(fix(PreferFrequenciesOverGroupBy, code), code)
    end
  end
end
