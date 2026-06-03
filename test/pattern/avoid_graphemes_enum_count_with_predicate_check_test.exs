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

    test "sum_by counting fn in two-step pipe" do
      code = ~s[String.graphemes(str) |> Enum.sum_by(fn "1" -> 1; _ -> 0 end)]
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] = check(code)
    end

    test "sum_by counting fn in three-step pipe" do
      code = ~s[str |> String.graphemes() |> Enum.sum_by(fn "1" -> 1; _ -> 0 end)]
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] = check(code)
    end

    test "sum_by counting fn in nested call" do
      code = ~s[Enum.sum_by(String.graphemes(str), fn "1" -> 1; _ -> 0 end)]
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] = check(code)
    end

    test "sum_by counting fn with variable catch-all" do
      code = ~s[String.graphemes(str) |> Enum.sum_by(fn "a" -> 1; _x -> 0 end)]
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] = check(code)
    end

    test "sum_by counting fn in longer pipeline" do
      code = """
      str
      |> String.trim()
      |> String.graphemes()
      |> Enum.sum_by(fn "1" -> 1; _ -> 0 end)
      """

      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] = check(code)
    end

    test "single precomposed accented literal is flagged (one codepoint)" do
      nfc = <<0x00E9::utf8>>

      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check(~s[Enum.count(String.graphemes(str), &(&1 == "#{nfc}"))])
    end

    test "space literal is flagged (one codepoint)" do
      assert [%Issue{rule: :avoid_graphemes_enum_count_with_predicate}] =
               check(~s[Enum.count(String.graphemes(str), &(&1 == " "))])
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
      assert check(~s[Enum.count(String.graphemes(str), fn c -> String.contains?(c, "1") end)]) ==
               []
    end

    test "Enum.sum_by on non-graphemes" do
      assert check(~s[Enum.sum_by(list, fn "1" -> 1; _ -> 0 end)]) == []
    end

    test "sum_by with non-counting function" do
      assert check(~s[String.graphemes(str) |> Enum.sum_by(fn x -> x end)]) == []
    end

    test "sum_by with 3 clauses" do
      code = ~s[String.graphemes(str) |> Enum.sum_by(fn "1" -> 1; "0" -> 0; _ -> 0 end)]
      assert check(code) == []
    end

    test "sum_by with non-literal match" do
      assert check(~s[String.graphemes(str) |> Enum.sum_by(fn x when x == "1" -> 1; _ -> 0 end)]) ==
               []
    end

    test "sum_by with non-1/0 return values" do
      assert check(~s[String.graphemes(str) |> Enum.sum_by(fn "1" -> 2; _ -> 0 end)]) == []
    end

    # Narrowing (decision 6a): only single-codepoint literals qualify.
    test "empty literal is not flagged" do
      assert check(~s[Enum.count(String.graphemes(str), &(&1 == ""))]) == []
    end

    test "multi-character literal is not flagged" do
      assert check(~s[Enum.count(String.graphemes(str), &(&1 == "ab"))]) == []
    end

    test "decomposed (two-codepoint) accent literal is not flagged" do
      # e + combining accent — two codepoints, dropped by the narrowing.
      nfd = "e" <> <<0x301::utf8>>
      assert check(~s[Enum.count(String.graphemes(str), &(&1 == "#{nfd}"))]) == []
    end
  end
end
