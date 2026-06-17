defmodule Credence.Pattern.AvoidGraphemesEnumCountFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidGraphemesEnumCount

  describe "no predicate → String.length" do
    test "nested call" do
      confirm_fix(
        fix(AvoidGraphemesEnumCount, "Enum.count(String.graphemes(str))"),
        "String.length(str)"
      )
    end

    test "two-step pipe" do
      confirm_fix(
        fix(AvoidGraphemesEnumCount, "String.graphemes(str) |> Enum.count()"),
        "String.length(str)"
      )
    end

    test "three-step pipe collapses to direct call" do
      confirm_fix(
        fix(AvoidGraphemesEnumCount, "str |> String.graphemes() |> Enum.count()"),
        "String.length(str)"
      )
    end

    test "keeps upstream pipeline, replaces last two steps" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCount,
          "str |> String.trim() |> String.graphemes() |> Enum.count()"
        ),
        "str |> String.trim() |> String.length()"
      )
    end
  end

  describe "no-ops" do
    test "String.length unchanged" do
      code = "String.length(str)"

      confirm_fix(fix(AvoidGraphemesEnumCount, code), code)
    end

    test "Enum.count on non-graphemes unchanged" do
      code = "Enum.count(list)"

      confirm_fix(fix(AvoidGraphemesEnumCount, code), code)
    end

    test "predicate case passes through unchanged" do
      code = ~S'String.graphemes(str) |> Enum.count(&(&1 == "a"))'

      confirm_fix(fix(AvoidGraphemesEnumCount, code), code)
    end

    test "nested predicate case passes through unchanged" do
      code = ~S'Enum.count(String.graphemes(str), &(&1 == "a"))'

      confirm_fix(fix(AvoidGraphemesEnumCount, code), code)
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

      assert check(AvoidGraphemesEnumCount, fix(AvoidGraphemesEnumCount, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count()
        def b(s), do: s |> String.trim() |> String.graphemes() |> Enum.count()
      end
      """

      assert valid_syntax?(fix(AvoidGraphemesEnumCount, code))
    end
  end
end
