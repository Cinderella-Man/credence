defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicateCheckTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.AvoidGraphemesEnumCountWithPredicate

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    AvoidGraphemesEnumCountWithPredicate.check(ast, [])
  end

  describe "flags graphemes piped to Enum.count with equality predicate" do
    test "capture predicate in two-step pipe" do
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check(~s[String.graphemes(str) |> Enum.count(&(&1 == "1"))])
    end

    test "capture predicate in three-step pipe" do
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check(~s[str |> String.graphemes() |> Enum.count(&(&1 == "1"))])
    end

    test "capture predicate in nested call" do
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check(~s[Enum.count(String.graphemes(str), &(&1 == "1"))])
    end

    test "fn predicate in two-step pipe" do
      code = ~s[String.graphemes(str) |> Enum.count(fn c -> c == "1" end)]
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] = check(code)
    end

    test "fn predicate in nested call" do
      code = ~s[Enum.count(String.graphemes(str), fn c -> c == "1" end)]
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] = check(code)
    end

    test "triple-equals capture predicate" do
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check(~s[Enum.count(String.graphemes(str), &(&1 === "a"))])
    end

    test "longer pipeline before graphemes" do
      code = """
      str
      |> String.trim()
      |> String.upcase()
      |> String.graphemes()
      |> Enum.count(&(&1 == "1"))
      """

      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] = check(code)
    end

    test "multiple violations in same module" do
      code = """
      defmodule Example do
        def a(str), do: String.graphemes(str) |> Enum.count(&(&1 == "1"))
        def b(str), do: Enum.count(String.graphemes(str), &(&1 == "1"))
      end
      """

      assert length(check(code)) == 2
    end
  end

  describe "does NOT flag" do
    test "Enum.count/2 with predicate on non-graphemes" do
      assert check(~s[Enum.count(list, &(&1 == "1"))]) == []
    end

    test "graphemes with Enum.count/1 (no predicate — handled by sibling rule)" do
      assert check("String.graphemes(str) |> Enum.count()") == []
    end

    test "Enum.count/1 on graphemes (handled by sibling rule)" do
      assert check("Enum.count(String.graphemes(str))") == []
    end

    test "graphemes piped to something other than Enum.count" do
      assert check(~s[String.graphemes(str) |> Enum.filter(&(&1 == "1"))]) == []
    end

    test "intermediate step between graphemes and count" do
      code = """
      str
      |> String.graphemes()
      |> Enum.map(& &1)
      |> Enum.count(&(&1 == "1"))
      """

      assert check(code) == []
    end

    test "graphemes stored then counted via variable" do
      code = """
      defmodule Example do
        def run(str) do
          g = String.graphemes(str)
          Enum.count(g, &(&1 == "1"))
        end
      end
      """

      assert check(code) == []
    end

    test "predicate with non-literal comparison" do
      assert check(~s[Enum.count(String.graphemes(str), &(&1 == var))]) == []
    end

    test "predicate with non-equality function" do
      assert check(~s[Enum.count(String.graphemes(str), &String.match?(&1, ~r/1/))]) == []
    end

    test "Enum.count/2 with non-capture function" do
      assert check(~s[Enum.count(String.graphemes(str), fn c -> String.contains?(c, "1") end)]) == []
    end
  end
end
