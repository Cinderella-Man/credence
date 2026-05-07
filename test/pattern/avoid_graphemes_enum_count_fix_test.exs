defmodule Credence.Pattern.AvoidGraphemesEnumCountFixTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.AvoidGraphemesEnumCount.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.AvoidGraphemesEnumCount.fix(code, [])
  end

  describe "no predicate → String.length" do
    test "nested call" do
      assert fix("Enum.count(String.graphemes(str))") == "String.length(str)"
    end

    test "two-step pipe" do
      assert fix("String.graphemes(str) |> Enum.count()") == "String.length(str)"
    end

    test "three-step pipe" do
      assert fix("str |> String.graphemes() |> Enum.count()") == "str |> String.length()"
    end
  end

  describe "with predicate → Stream.unfold" do
    test "two-step pipe with predicate" do
      input = "String.graphemes(str) |> Enum.count(&(&1 == \"a\"))"
      expected = "Stream.unfold(str, &String.next_grapheme/1) |> Enum.count(&(&1 == \"a\"))"
      assert fix(input) == expected
    end

    test "nested call with predicate" do
      input = "Enum.count(String.graphemes(str), &(&1 == \"a\"))"
      expected = "Enum.count(Stream.unfold(str, &String.next_grapheme/1), &(&1 == \"a\"))"
      assert fix(input) == expected
    end

    test "preserves fn predicate" do
      input = "Enum.count(String.graphemes(str), fn g -> g == \"x\" end)"
      expected = "Enum.count(Stream.unfold(str, &String.next_grapheme/1), fn g -> g == \"x\" end)"
      assert fix(input) == expected
    end
  end

  describe "no-ops" do
    test "String.length unchanged" do
      code = "String.length(str)"
      assert fix(code) == code
    end

    test "Enum.count on non-graphemes unchanged" do
      code = "Enum.count(list, &(&1 > 0))"
      assert fix(code) == code
    end
  end

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count()
        def b(s), do: Enum.count(String.graphemes(s))
        def c(s), do: String.graphemes(s) |> Enum.count(&(&1 == "x"))
        def d(s), do: Enum.count(String.graphemes(s), &(&1 == "x"))
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count()
        def b(s), do: String.graphemes(s) |> Enum.count(&(&1 == "x"))
      end
      """

      assert {:ok, _} = Code.string_to_quoted(fix(code))
    end
  end
end
