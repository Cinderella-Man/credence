defmodule Credence.Pattern.AvoidGraphemesLengthFixTest do
  use ExUnit.Case

  defp fix(code) do
    Credence.Pattern.AvoidGraphemesLength.fix(code, [])
  end

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.AvoidGraphemesLength.check(ast, [])
  end

  describe "replaces with String.length" do
    test "nested call" do
      assert fix("length(String.graphemes(str))") == "String.length(str)"
    end

    test "two-step pipe" do
      assert fix("String.graphemes(str) |> length()") == "String.length(str)"
    end

    test "three-step pipe collapses to direct call" do
      assert fix("s |> String.graphemes() |> length()") == "String.length(s)"
    end

    test "keeps upstream pipeline, replaces last two steps" do
      assert fix("s |> String.trim() |> String.graphemes() |> length()") ==
               "s |> String.trim() |> String.length()"
    end

    test "multiple issues in one module" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> length()
        def b(s), do: length(String.graphemes(s))
        def c(s), do: s |> String.graphemes() |> length()
      end
      """

      expected =
        String.trim_trailing("""
        defmodule Example do
          def a(s), do: String.length(s)
          def b(s), do: String.length(s)
          def c(s), do: String.length(s)
        end
        """)

      assert fix(code) == expected
    end
  end

  describe "no-ops" do
    test "String.length unchanged" do
      assert fix("String.length(str)") == "String.length(str)"
    end

    test "unrelated length unchanged" do
      assert fix("length(list)") == "length(list)"
    end

    test "graphemes piped to something else unchanged" do
      code = "String.graphemes(str) |> Enum.reverse()"
      assert fix(code) == code
    end
  end

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> length()
        def b(s), do: length(String.graphemes(s))
        def c(s), do: s |> String.graphemes() |> length()
      end
      """

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      assert {:ok, _} = Code.string_to_quoted(fix("String.graphemes(str) |> length()"))
    end
  end
end
