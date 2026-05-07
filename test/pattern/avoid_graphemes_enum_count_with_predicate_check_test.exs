defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicateCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.AvoidGraphemesEnumCountWithPredicate.check(ast, [])
  end

  describe "fixable?" do
    test "reports as NOT fixable" do
      assert Credence.Pattern.AvoidGraphemesEnumCountWithPredicate.fixable?() == false
    end
  end

  describe "flags graphemes piped to Enum.count with predicate" do
    test "two-step pipe with capture predicate" do
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check("String.graphemes(str) |> Enum.count(&(&1 == \"a\"))")
    end

    test "three-step pipe with capture predicate" do
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check("str |> String.graphemes() |> Enum.count(&(&1 == \"a\"))")
    end

    test "nested call with capture predicate" do
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check("Enum.count(String.graphemes(str), &(&1 == \"a\"))")
    end

    test "nested call with fn predicate" do
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check("Enum.count(String.graphemes(str), fn g -> g == \"x\" end)")
    end

    test "longer pipeline before graphemes" do
      code = """
      str
      |> String.trim()
      |> String.downcase()
      |> String.graphemes()
      |> Enum.count(&(&1 == "a"))
      """

      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] = check(code)
    end

    test "multiple violations in same module" do
      code = """
      defmodule Example do
        def vowels(str), do: String.graphemes(str) |> Enum.count(&(&1 in ~w(a e i o u)))
        def spaces(str), do: Enum.count(String.graphemes(str), &(&1 == " "))
      end
      """

      assert length(check(code)) == 2
    end
  end

  describe "does NOT flag" do
    test "Enum.count/1 without predicate (handled by separate rule)" do
      assert check("String.graphemes(str) |> Enum.count()") == []
    end

    test "nested Enum.count/1 without predicate" do
      assert check("Enum.count(String.graphemes(str))") == []
    end

    test "String.length/1" do
      assert check("String.length(str)") == []
    end

    test "Enum.count/2 on non-graphemes" do
      assert check("Enum.count(list, &(&1 > 0))") == []
    end

    test "graphemes piped to something other than Enum.count" do
      assert check("String.graphemes(str) |> Enum.filter(&(&1 == \"a\"))") == []
    end

    test "intermediate step between graphemes and count" do
      code = """
      str
      |> String.graphemes()
      |> Enum.filter(&(&1 != " "))
      |> Enum.count(&(&1 == "a"))
      """

      assert check(code) == []
    end

    test "graphemes stored then counted via variable" do
      code = """
      defmodule Example do
        def run(str) do
          g = String.graphemes(str)
          Enum.count(g, &(&1 == "a"))
        end
      end
      """

      assert check(code) == []
    end

    test "String.codepoints piped to Enum.count with predicate" do
      assert check("String.codepoints(str) |> Enum.count(&(&1 == \"a\"))") == []
    end
  end
end
