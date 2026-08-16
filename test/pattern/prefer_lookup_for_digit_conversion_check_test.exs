defmodule Credence.Pattern.PreferLookupForDigitConversionCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.PreferLookupForDigitConversion

  describe "flags" do
    test "16 separate hex digit clauses" do
      assert flagged?(PreferLookupForDigitConversion, """
             defmodule Solution do
               defp hex_digit(0), do: "0"
               defp hex_digit(1), do: "1"
               defp hex_digit(2), do: "2"
               defp hex_digit(3), do: "3"
               defp hex_digit(4), do: "4"
               defp hex_digit(5), do: "5"
               defp hex_digit(6), do: "6"
               defp hex_digit(7), do: "7"
               defp hex_digit(8), do: "8"
               defp hex_digit(9), do: "9"
               defp hex_digit(10), do: "A"
               defp hex_digit(11), do: "B"
               defp hex_digit(12), do: "C"
               defp hex_digit(13), do: "D"
               defp hex_digit(14), do: "E"
               defp hex_digit(15), do: "F"
             end
             """)
    end

    test "reports an issue with the correct rule name" do
      issues =
        check(PreferLookupForDigitConversion, """
        defmodule Solution do
          defp hex_digit(0), do: "0"
          defp hex_digit(1), do: "1"
          defp hex_digit(2), do: "2"
          defp hex_digit(3), do: "3"
          defp hex_digit(4), do: "4"
          defp hex_digit(5), do: "5"
          defp hex_digit(6), do: "6"
          defp hex_digit(7), do: "7"
          defp hex_digit(8), do: "8"
          defp hex_digit(9), do: "9"
          defp hex_digit(10), do: "A"
          defp hex_digit(11), do: "B"
          defp hex_digit(12), do: "C"
          defp hex_digit(13), do: "D"
          defp hex_digit(14), do: "E"
          defp hex_digit(15), do: "F"
        end
        """)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :prefer_lookup_for_digit_conversion
      assert issue.meta.line != nil
    end
  end

  describe "leaves good code alone" do
    test "single clause function" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               defp hex_digit(remainder) do
                 "0123456789ABCDEF"
                 |> String.at(remainder)
               end
             end
             """)
    end

    test "only numeric digit clauses (0-9, no hex letters)" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               defp digit(0), do: "0"
               defp digit(1), do: "1"
               defp digit(2), do: "2"
               defp digit(3), do: "3"
               defp digit(4), do: "4"
               defp digit(5), do: "5"
               defp digit(6), do: "6"
               defp digit(7), do: "7"
               defp digit(8), do: "8"
               defp digit(9), do: "9"
             end
             """)
    end

    test "non-hex mapping" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               defp letter(0), do: "a"
               defp letter(1), do: "b"
               defp letter(2), do: "c"
             end
             """)
    end

    test "functions with arity > 1" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               defp foo(0, x), do: x
               defp foo(1, x), do: x + 1
             end
             """)
    end

    test "public functions" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
               def hex_digit(0), do: "0"
               def hex_digit(1), do: "1"
             end
             """)
    end

    test "leading shadowing clause makes the mapping incomplete (first-match wins)" do
      # The first hex_digit(10) clause returns "Z" at runtime; the later
      # hex_digit(10) -> "A" is unreachable. Reading first-match, the mapping for
      # 10 is "Z" (not "A"), so this is NOT the identity hex mapping and must not
      # be flagged — otherwise the fix would silently change the answer for 10.
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Maybe do
               defp hex_digit(10), do: "Z"
               defp hex_digit(0), do: "0"
               defp hex_digit(1), do: "1"
               defp hex_digit(2), do: "2"
               defp hex_digit(3), do: "3"
               defp hex_digit(4), do: "4"
               defp hex_digit(5), do: "5"
               defp hex_digit(6), do: "6"
               defp hex_digit(7), do: "7"
               defp hex_digit(8), do: "8"
               defp hex_digit(9), do: "9"
               defp hex_digit(10), do: "A"
               defp hex_digit(11), do: "B"
               defp hex_digit(12), do: "C"
               defp hex_digit(13), do: "D"
               defp hex_digit(14), do: "E"
               defp hex_digit(15), do: "F"
             end
             """)
    end

    test "empty module" do
      assert clean?(PreferLookupForDigitConversion, """
             defmodule Good do
             end
             """)
    end
  end

  # ── D6/C12(c): the SHAPE half of over-fitting ──────────────────────────
  #
  # docs/12 named this rule as over-fit, and probing it agreed — but not where
  # the doc said. The matcher was keyed to the UPPERCASE hex alphabet alone, so
  # of the two shapes an author writes it fired on one. Lowercase is not exotic:
  # git SHAs, MD5 digests and CSS colours are all lowercase hex, and
  # `Base.encode16` carries a `case: :lower` option because both are common.
  #
  # The generalisation is exact rather than a widening guess: the repair reads
  # the alphabet back off the clauses it matched, so a lowercase table can only
  # produce a lowercase lookup.
  describe "both hex alphabets" do
    defp hex_table(name, alphabet) do
      clauses =
        Enum.map_join(0..15, "\n", fn i ->
          "  defp #{name}(#{i}), do: #{inspect(String.at(alphabet, i))}"
        end)

      "defmodule HexT do\n" <> clauses <> "\n\n  def go(n), do: #{name}(n)\nend\n"
    end

    test "a lowercase table is detected" do
      source = hex_table("hex_digit", "0123456789abcdef")

      assert [%Issue{rule: :prefer_lookup_for_digit_conversion}] =
               check(PreferLookupForDigitConversion, source)
    end

    test "an uppercase table is still detected" do
      source = hex_table("hex_digit", "0123456789ABCDEF")

      assert [%Issue{rule: :prefer_lookup_for_digit_conversion}] =
               check(PreferLookupForDigitConversion, source)
    end

    test "the repair keeps the alphabet it found — lowercase stays lowercase" do
      fixed = fix(PreferLookupForDigitConversion, hex_table("hex_digit", "0123456789abcdef"))

      assert fixed =~ ~s("0123456789abcdef")
      refute fixed =~ ~s("0123456789ABCDEF")
    end

    test "and uppercase stays uppercase" do
      fixed = fix(PreferLookupForDigitConversion, hex_table("hex_digit", "0123456789ABCDEF"))

      assert fixed =~ ~s("0123456789ABCDEF")
      refute fixed =~ ~s("0123456789abcdef")
    end

    # The reason a wider matcher is safe here: the rewrite is behaviour-identical
    # on the whole domain, out-of-range input included. Executed through
    # `call_fixed/4`, not argued from the shapes.
    test "the rewritten function answers identically for 0..15 and raises alike outside" do
      for {tag, alphabet} <- [{"Lo", "0123456789abcdef"}, {"Up", "0123456789ABCDEF"}] do
        source = hex_table("hex_digit", alphabet) |> String.replace("HexT", "HexEq" <> tag)
        fixed = fix(PreferLookupForDigitConversion, source)
        mod = String.to_atom("Elixir.HexEq" <> tag)

        for i <- 0..15 do
          assert call_fixed(source, mod, :go, [i]) == call_fixed(fixed, mod, :go, [i])
        end

        for i <- [-1, 16, 100] do
          assert outcome(source, mod, i) == outcome(fixed, mod, i)
        end
      end
    end

    defp outcome(code, mod, arg) do
      {:ok, call_fixed(code, mod, :go, [arg])}
    rescue
      e -> {:raised, e.__struct__}
    end

    # A near-miss control. Fifteen of the sixteen clauses is not the idiom, and
    # the missing one is exactly where a wider matcher would start guessing.
    test "an incomplete table is left alone" do
      clauses =
        Enum.map_join(1..15, "\n", fn i ->
          "  defp hex_digit(#{i}), do: #{inspect(String.at("0123456789abcdef", i))}"
        end)

      assert check(PreferLookupForDigitConversion, "defmodule HexT do\n" <> clauses <> "\nend\n") ==
               []
    end

    # And a mixed-case table is not either alphabet, so it is not this idiom.
    test "a mixed-case table is left alone" do
      assert check(PreferLookupForDigitConversion, hex_table("hex_digit", "0123456789AbCdEf")) ==
               []
    end
  end
end
