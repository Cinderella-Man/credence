defmodule Credence.Pattern.AvoidGraphemesEnumCountCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.AvoidGraphemesEnumCount.check(ast, [])
  end

  describe "flags graphemes piped to Enum.count" do
    test "three-step pipe" do
      code = "str |> String.graphemes() |> Enum.count()"
      assert [%Issue{rule: :avoid_graphemes_enum_count}] = check(code)
    end

    test "two-step pipe" do
      code = "String.graphemes(str) |> Enum.count()"
      assert [%Issue{rule: :avoid_graphemes_enum_count}] = check(code)
    end

    test "nested call" do
      code = "Enum.count(String.graphemes(str))"
      assert [%Issue{rule: :avoid_graphemes_enum_count}] = check(code)
    end

    test "nested call with predicate" do
      code = "Enum.count(String.graphemes(str), &(&1 == \"a\"))"
      assert [%Issue{rule: :avoid_graphemes_enum_count}] = check(code)
    end

    test "pipe with predicate" do
      code = "String.graphemes(str) |> Enum.count(&(&1 == \"a\"))"
      assert [%Issue{rule: :avoid_graphemes_enum_count}] = check(code)
    end

    test "longer pipeline before graphemes" do
      code = """
      str
      |> String.trim()
      |> String.upcase()
      |> String.graphemes()
      |> Enum.count()
      """

      assert [%Issue{rule: :avoid_graphemes_enum_count}] = check(code)
    end

    test "multiple violations in same module" do
      code = """
      defmodule Example do
        def count(str), do: String.graphemes(str) |> Enum.count()
        def vowels(str), do: String.graphemes(str) |> Enum.count(&(&1 in ~w(a e i o u)))
      end
      """

      assert length(check(code)) == 2
    end
  end

  describe "does NOT flag" do
    test "String.length/1" do
      assert check("String.length(str)") == []
    end

    test "Enum.count on non-graphemes" do
      assert check("Enum.count(list)") == []
    end

    test "graphemes piped to something other than Enum.count" do
      assert check("String.graphemes(str) |> Enum.reverse()") == []
    end

    test "intermediate step between graphemes and count" do
      code = """
      str
      |> String.graphemes()
      |> Enum.map(& &1)
      |> Enum.count()
      """

      assert check(code) == []
    end

    test "filter between graphemes and count" do
      code = """
      str
      |> String.graphemes()
      |> Enum.filter(&(&1 != " "))
      |> Enum.count()
      """

      assert check(code) == []
    end

    test "graphemes stored then counted via variable" do
      code = """
      defmodule Example do
        def run(str) do
          g = String.graphemes(str)
          Enum.count(g)
        end
      end
      """

      assert check(code) == []
    end

    test "String.codepoints piped to Enum.count" do
      assert check("String.codepoints(str) |> Enum.count()") == []
    end

    test "Enum.count/2 on non-graphemes with predicate" do
      assert check("Enum.count(list, &(&1 > 0))") == []
    end
  end
end
