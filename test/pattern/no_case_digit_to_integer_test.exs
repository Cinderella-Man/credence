defmodule Credence.Pattern.NoCaseDigitToIntegerTest do
  use ExUnit.Case

  alias Credence.Pattern.NoCaseDigitToInteger

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCaseDigitToInteger.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  defp fix(code) do
    ast = Sourceror.parse_string!(code)
    patches = NoCaseDigitToInteger.fix_patches(ast, [])
    if patches == [], do: code, else: Sourceror.patch_string(code, patches)
  end

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags case mapping digit strings to integers" do
    test "all 10 digits in ascending order" do
      assert flagged?("""
             case digit do
               "0" -> 0
               "1" -> 1
               "2" -> 2
               "3" -> 3
               "4" -> 4
               "5" -> 5
               "6" -> 6
               "7" -> 7
               "8" -> 8
               "9" -> 9
             end
             """)
    end

    test "all 10 digits in descending order" do
      assert flagged?("""
             case digit do
               "9" -> 9
               "8" -> 8
               "7" -> 7
               "6" -> 6
               "5" -> 5
               "4" -> 4
               "3" -> 3
               "2" -> 2
               "1" -> 1
               "0" -> 0
             end
             """)
    end

    test "digits in arbitrary order" do
      assert flagged?("""
             case ch do
               "3" -> 3
               "7" -> 7
               "0" -> 0
               "9" -> 9
               "1" -> 1
               "5" -> 5
               "8" -> 8
               "2" -> 2
               "4" -> 4
               "6" -> 6
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag non-digit case expressions" do
    test "fewer than 10 clauses" do
      assert clean?("""
             case digit do
               "0" -> 0
               "1" -> 1
               "2" -> 2
             end
             """)
    end

    test "11 clauses (includes wildcard)" do
      assert clean?("""
             case digit do
               "0" -> 0
               "1" -> 1
               "2" -> 2
               "3" -> 3
               "4" -> 4
               "5" -> 5
               "6" -> 6
               "7" -> 7
               "8" -> 8
               "9" -> 9
               _ -> :error
             end
             """)
    end

    test "atom patterns" do
      assert clean?("""
             case status do
               :ok -> 0
               :error -> 1
             end
             """)
    end

    test "integer-to-string (reverse direction)" do
      assert clean?("""
             case n do
               0 -> "0"
               1 -> "1"
               2 -> "2"
               3 -> "3"
               4 -> "4"
               5 -> "5"
               6 -> "6"
               7 -> "7"
               8 -> "8"
               9 -> "9"
             end
             """)
    end

    test "wrong integer values" do
      assert clean?("""
             case digit do
               "0" -> 1
               "1" -> 2
               "2" -> 3
               "3" -> 4
               "4" -> 5
               "5" -> 6
               "6" -> 7
               "7" -> 8
               "8" -> 9
               "9" -> 10
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — auto-fix produces expected output
  # ═══════════════════════════════════════════════════════════════════

  describe "auto-fix" do
    test "replaces digit case with String.to_integer/1" do
      code = """
      case digit do
        "0" -> 0
        "1" -> 1
        "2" -> 2
        "3" -> 3
        "4" -> 4
        "5" -> 5
        "6" -> 6
        "7" -> 7
        "8" -> 8
        "9" -> 9
      end
      """

      fixed = fix(code)
      assert fixed =~ "String.to_integer(digit)"
      refute fixed =~ "case digit do"
    end

    test "reverses order preserved in fix" do
      code = """
      case ch do
        "9" -> 9
        "8" -> 8
        "7" -> 7
        "6" -> 6
        "5" -> 5
        "4" -> 4
        "3" -> 3
        "2" -> 2
        "1" -> 1
        "0" -> 0
      end
      """

      fixed = fix(code)
      assert fixed =~ "String.to_integer(ch)"
      refute fixed =~ "case ch do"
    end
  end
end
