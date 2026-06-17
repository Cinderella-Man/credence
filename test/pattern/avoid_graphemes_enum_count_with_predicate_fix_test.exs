defmodule Credence.Pattern.AvoidGraphemesEnumCountWithPredicateFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidGraphemesEnumCountWithPredicate

  describe "predicate → String.count" do
    test "nested call with capture predicate" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'Enum.count(String.graphemes(str), &(&1 == "1"))'
        ),
        ~S'String.count(str, "1")'
      )
    end

    test "two-step pipe with capture predicate" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'String.graphemes(str) |> Enum.count(&(&1 == "1"))'
        ),
        ~S'String.count(str, "1")'
      )
    end

    test "three-step pipe collapses to direct call" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'str |> String.graphemes() |> Enum.count(&(&1 == "1"))'
        ),
        ~S'String.count(str, "1")'
      )
    end

    test "keeps upstream pipeline, replaces last two steps" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'str |> String.trim() |> String.graphemes() |> Enum.count(&(&1 == "1"))'
        ),
        ~S'str |> String.trim() |> String.count("1")'
      )
    end

    test "fn predicate in nested call" do
      code = ~S'Enum.count(String.graphemes(str), fn c -> c == "1" end)'

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), ~S'String.count(str, "1")')
    end

    test "triple-equals capture predicate" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'Enum.count(String.graphemes(str), &(&1 === "a"))'
        ),
        ~S'String.count(str, "a")'
      )
    end

    test "sum_by counting fn in nested call" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'Enum.sum_by(String.graphemes(str), fn "1" -> 1; _ -> 0 end)'
        ),
        ~S'String.count(str, "1")'
      )
    end

    test "sum_by counting fn in two-step pipe" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'String.graphemes(str) |> Enum.sum_by(fn "1" -> 1; _ -> 0 end)'
        ),
        ~S'String.count(str, "1")'
      )
    end

    test "sum_by counting fn in three-step pipe" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'str |> String.graphemes() |> Enum.sum_by(fn "1" -> 1; _ -> 0 end)'
        ),
        ~S'String.count(str, "1")'
      )
    end

    test "sum_by counting fn keeps upstream pipeline" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'str |> String.trim() |> String.graphemes() |> Enum.sum_by(fn "a" -> 1; _ -> 0 end)'
        ),
        ~S'str |> String.trim() |> String.count("a")'
      )
    end

    test "sum_by counting fn with variable catch-all" do
      confirm_fix(
        fix(
          AvoidGraphemesEnumCountWithPredicate,
          ~S'String.graphemes(str) |> Enum.sum_by(fn "x" -> 1; _rest -> 0 end)'
        ),
        ~S'String.count(str, "x")'
      )
    end
  end

  describe "no-ops" do
    test "String.count unchanged" do
      code = ~S'String.count(str, "1")'

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end

    test "Enum.count on non-graphemes unchanged" do
      code = ~S'Enum.count(list, &(&1 == "1"))'

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end

    test "no-predicate case passes through (handled by sibling rule)" do
      code = "String.graphemes(str) |> Enum.count()"

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end

    test "non-literal predicate passes through" do
      code = "Enum.count(String.graphemes(str), &(&1 == var))"

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end

    test "sum_by on non-graphemes unchanged" do
      code = ~S'Enum.sum_by(list, fn "1" -> 1; _ -> 0 end)'

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end

    test "sum_by with non-counting function unchanged" do
      code = "String.graphemes(str) |> Enum.sum_by(fn x -> x end)"

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end

    test "sum_by with non-1/0 returns unchanged" do
      code = ~S'String.graphemes(str) |> Enum.sum_by(fn "1" -> 2; _ -> 0 end)'

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end

    # Narrowing (decision 6a): non-single-codepoint literals are left untouched.
    test "empty literal passes through" do
      code = ~S'Enum.count(String.graphemes(str), &(&1 == ""))'

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end

    test "multi-character literal passes through" do
      code = ~S'Enum.count(String.graphemes(str), &(&1 == "ab"))'

      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end

    test "decomposed (two-codepoint) accent literal passes through" do
      nfd = "e" <> <<0x301::utf8>>
      code = ~s[Enum.count(String.graphemes(str), &(&1 == "#{nfd}"))]
      confirm_fix(fix(AvoidGraphemesEnumCountWithPredicate, code), code)
    end
  end

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count(&(&1 == "1"))
        def b(s), do: Enum.count(String.graphemes(s), &(&1 == "1"))
        def c(s), do: s |> String.graphemes() |> Enum.count(&(&1 == "1"))
        def d(s), do: String.graphemes(s) |> Enum.sum_by(fn "1" -> 1; _ -> 0 end)
        def e(s), do: Enum.sum_by(String.graphemes(s), fn "1" -> 1; _ -> 0 end)
      end
      """

      assert check(
               AvoidGraphemesEnumCountWithPredicate,
               fix(AvoidGraphemesEnumCountWithPredicate, code)
             ) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(s), do: String.graphemes(s) |> Enum.count(&(&1 == "1"))
        def b(s), do: s |> String.trim() |> String.graphemes() |> Enum.count(&(&1 == "1"))
        def c(s), do: String.graphemes(s) |> Enum.sum_by(fn "1" -> 1; _ -> 0 end)
      end
      """

      assert valid_syntax?(fix(AvoidGraphemesEnumCountWithPredicate, code))
    end
  end
end
