defmodule Credence.Pattern.AvoidGraphemesLengthFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidGraphemesLength

  describe "replaces with String.length" do
    test "nested call" do
      assert fix(AvoidGraphemesLength, "length(String.graphemes(str))") == "String.length(str)"
    end

    test "two-step pipe" do
      assert fix(AvoidGraphemesLength, "String.graphemes(str) |> length()") ==
               "String.length(str)"
    end

    test "three-step pipe collapses to direct call" do
      assert fix(AvoidGraphemesLength, "s |> String.graphemes() |> length()") ==
               "String.length(s)"
    end

    test "keeps upstream pipeline, replaces last two steps" do
      assert fix(AvoidGraphemesLength, "s |> String.trim() |> String.graphemes() |> length()") ==
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

      expected = """
      defmodule Example do
        def a(s), do: String.length(s)
        def b(s), do: String.length(s)
        def c(s), do: String.length(s)
      end
      """

      assert fix(AvoidGraphemesLength, code) == expected
    end
  end

  describe "no-ops" do
    test "String.length unchanged" do
      assert fix(AvoidGraphemesLength, "String.length(str)") == "String.length(str)"
    end

    test "unrelated length unchanged" do
      assert fix(AvoidGraphemesLength, "length(list)") == "length(list)"
    end

    test "graphemes piped to something else unchanged" do
      code = "String.graphemes(str) |> Enum.reverse()"
      assert fix(AvoidGraphemesLength, code) == code
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

      assert check(AvoidGraphemesLength, fix(AvoidGraphemesLength, code)) == []
    end

    test "fixed code is valid Elixir" do
      assert {:ok, _} =
               Sourceror.parse_string(
                 fix(AvoidGraphemesLength, "String.graphemes(str) |> length()")
               )
    end
  end
end
