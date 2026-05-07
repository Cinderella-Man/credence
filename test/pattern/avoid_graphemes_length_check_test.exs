defmodule Credence.Pattern.AvoidGraphemesLengthCheckTest do
  use ExUnit.Case

  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.AvoidGraphemesLength.check(ast, [])
  end

  describe "flags graphemes piped to length" do
    test "three-step pipe" do
      assert [%Issue{rule: :avoid_graphemes_length}] =
               check("str |> String.graphemes() |> length()")
    end

    test "two-step pipe" do
      assert [%Issue{rule: :avoid_graphemes_length}] =
               check("String.graphemes(str) |> length()")
    end

    test "nested call" do
      assert [%Issue{rule: :avoid_graphemes_length}] =
               check("length(String.graphemes(str))")
    end

    test "longer pipeline before graphemes" do
      code = """
      str
      |> String.trim()
      |> String.upcase()
      |> String.graphemes()
      |> length()
      """

      assert [%Issue{rule: :avoid_graphemes_length}] = check(code)
    end

    test "inside Enum.map" do
      code = """
      Enum.map(list, fn x ->
        String.graphemes(x) |> length()
      end)
      """

      assert [%Issue{rule: :avoid_graphemes_length}] = check(code)
    end

    test "nested pipeline in tuple" do
      assert [%Issue{rule: :avoid_graphemes_length}] =
               check("Enum.map(list, &{&1, &1 |> String.graphemes() |> length()})")
    end
  end

  describe "does NOT flag" do
    test "String.length/1" do
      assert check("String.length(str)") == []
    end

    test "graphemes piped to something other than length" do
      assert check("String.graphemes(str) |> Enum.reverse()") == []
    end

    test "intermediate step between graphemes and length" do
      code = """
      str
      |> String.graphemes()
      |> Enum.map(& &1)
      |> length()
      """

      assert check(code) == []
    end

    test "filter between graphemes and length" do
      code = """
      str
      |> String.graphemes()
      |> Enum.filter(&(&1 != " "))
      |> length()
      """

      assert check(code) == []
    end

    test "unrelated length usage" do
      assert check("length(list)") == []
    end

    test "graphemes stored then counted via variable" do
      code = """
      defmodule Example do
        def run(str) do
          g = String.graphemes(str)
          length(g)
        end
      end
      """

      assert check(code) == []
    end
  end
end
