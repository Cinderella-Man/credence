defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicateFixTest do
  use ExUnit.Case

  alias Credence.Pattern.AvoidGraphemesEnumCountWithPredicate

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    AvoidGraphemesEnumCountWithPredicate.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(AvoidGraphemesEnumCountWithPredicate, code, [])
  end

  describe "predicate → String.count" do
    test "nested call with capture predicate" do
      assert fix(~s[Enum.count(String.graphemes(str), &(&1 == "1"))]) ==
               ~s[String.count(str, "1")]
    end

    test "two-step pipe with capture predicate" do
      assert fix(~s[String.graphemes(str) |> Enum.count(&(&1 == "1"))]) ==
               ~s[String.count(str, "1")]
    end

    test "three-step pipe collapses to direct call" do
      assert fix(~s[str |> String.graphemes() |> Enum.count(&(&1 == "1"))]) ==
               ~s[String.count(str, "1")]
    end

    test "keeps upstream pipeline, replaces last two steps" do
      assert fix(~s[str |> String.trim() |> String.graphemes() |> Enum.count(&(&1 == "1"))]) ==
               ~s[str |> String.trim() |> String.count("1")]
    end

    test "fn predicate in nested call" do
      code = ~s[Enum.count(String.graphemes(str), fn c -> c == "1" end)]
      assert fix(code) == ~s[String.count(str, "1")]
    end

    test "triple-equals capture predicate" do
      assert fix(~s[Enum.count(String.graphemes(str), &(&1 === "a"))]) ==
               ~s[String.count(str, "a")]
    end
  end

  describe "no-ops" do
    test "String.count unchanged" do
      code = ~s[String.count(str, "1")]
      assert fix(code) == code
    end

    test "Enum.count on non-graphemes unchanged" do
      code = ~s[Enum.count(list, &(&1 == "1"))]
      assert fix(code) == code
    end

    test "no-predicate case passes through (handled by sibling rule)" do
      code = "String.graphemes(str) |> Enum.count()"
      assert fix(code) == code
    end

    test "non-literal predicate passes through" do
      code = ~s[Enum.count(String.graphemes(str), &(&1 == var))]
      assert fix(code) == code
    end
  end

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count(&(&1 == "1"))
        def b(s), do: Enum.count(String.graphemes(s), &(&1 == "1"))
        def c(s), do: s |> String.graphemes() |> Enum.count(&(&1 == "1"))
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count(&(&1 == "1"))
        def b(s), do: s |> String.trim() |> String.graphemes() |> Enum.count(&(&1 == "1"))
      end
      """

      assert {:ok, _} = Sourceror.parse_string(fix(code))
    end
  end
end
