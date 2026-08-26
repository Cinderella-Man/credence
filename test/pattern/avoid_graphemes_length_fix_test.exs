defmodule Credence.Pattern.AvoidGraphemesLengthFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidGraphemesLength

  describe "replaces with String.length" do
    test "nested call" do
      confirm_fix(
        fix(AvoidGraphemesLength, "length(String.graphemes(str))"),
        "String.length(str)"
      )
    end

    test "two-step pipe" do
      confirm_fix(
        fix(AvoidGraphemesLength, "String.graphemes(str) |> length()"),
        "String.length(str)"
      )
    end

    test "three-step pipe collapses to direct call" do
      confirm_fix(
        fix(AvoidGraphemesLength, "s |> String.graphemes() |> length()"),
        "String.length(s)"
      )
    end

    test "keeps upstream pipeline, replaces last two steps" do
      confirm_fix(
        fix(AvoidGraphemesLength, "s |> String.trim() |> String.graphemes() |> length()"),
        "s |> String.trim() |> String.length()"
      )
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

      confirm_fix(fix(AvoidGraphemesLength, code), expected)
    end
  end

  describe "no-ops" do
    test "invalid String.graphemes arities are unchanged" do
      for code <- [
            "String.graphemes() |> length()",
            "value |> String.graphemes(extra) |> length()"
          ] do
        confirm_fix(fix(AvoidGraphemesLength, code), code)
      end
    end

    test "String alias that names a custom module is unchanged" do
      code = """
      alias CustomString, as: String
      length(String.graphemes(value))
      """

      confirm_fix(fix(AvoidGraphemesLength, code), code)
    end

    test "String.length unchanged" do
      confirm_fix(fix(AvoidGraphemesLength, "String.length(str)"), "String.length(str)")
    end

    test "unrelated length unchanged" do
      confirm_fix(fix(AvoidGraphemesLength, "length(list)"), "length(list)")
    end

    test "graphemes piped to something else unchanged" do
      code = "String.graphemes(str) |> Enum.reverse()"

      confirm_fix(fix(AvoidGraphemesLength, code), code)
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
      assert valid_syntax?(fix(AvoidGraphemesLength, "String.graphemes(str) |> length()"))
    end
  end
end
