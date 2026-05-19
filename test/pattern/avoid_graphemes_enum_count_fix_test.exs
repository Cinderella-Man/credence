defmodule Credence.Pattern.AvoidGraphemesEnumCountFixTest do
  use ExUnit.Case

  alias Credence.Pattern.AvoidGraphemesEnumCount

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    AvoidGraphemesEnumCount.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(AvoidGraphemesEnumCount, code, [])
  end

  describe "no predicate → String.length" do
    test "nested call" do
      assert fix("Enum.count(String.graphemes(str))") == "String.length(str)"
    end

    test "two-step pipe" do
      assert fix("String.graphemes(str) |> Enum.count()") == "String.length(str)"
    end

    test "three-step pipe collapses to direct call" do
      assert fix("str |> String.graphemes() |> Enum.count()") == "String.length(str)"
    end

    test "keeps upstream pipeline, replaces last two steps" do
      assert fix("str |> String.trim() |> String.graphemes() |> Enum.count()") ==
               "str |> String.trim() |> String.length()"
    end
  end

  describe "no-ops" do
    test "String.length unchanged" do
      code = "String.length(str)"
      assert fix(code) == code
    end

    test "Enum.count on non-graphemes unchanged" do
      code = "Enum.count(list)"
      assert fix(code) == code
    end

    test "predicate case passes through unchanged" do
      code = "String.graphemes(str) |> Enum.count(&(&1 == \"a\"))"
      assert fix(code) == code
    end

    test "nested predicate case passes through unchanged" do
      code = "Enum.count(String.graphemes(str), &(&1 == \"a\"))"
      assert fix(code) == code
    end
  end

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count()
        def b(s), do: Enum.count(String.graphemes(s))
        def c(s), do: s |> String.graphemes() |> Enum.count()
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count()
        def b(s), do: s |> String.trim() |> String.graphemes() |> Enum.count()
      end
      """

      assert {:ok, _} = Sourceror.parse_string(fix(code))
    end
  end
end
