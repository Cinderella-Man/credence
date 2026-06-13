defmodule Credence.Pattern.PreferRemoveUnusedPrivateFnParamCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferRemoveUnusedPrivateFnParam

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should be flagged
  # ═══════════════════════════════════════════════════════════════════

  describe "flags unused private function parameters" do
    test "single clause with underscore-prefixed unused param" do
      assert flagged?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute(x, _unused), do: x + 1
             end
             """)
    end

    test "single clause with non-underscore unused param" do
      assert flagged?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute(x, table), do: x + 1
             end
             """)
    end

    test "multi-clause function with unused param in all clauses" do
      assert flagged?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute([], _table), do: 0
               defp compute([h | t], _table), do: h + compute(t, nil)
             end
             """)
    end

    test "recursive LCS-style function with unused table param" do
      assert flagged?(PreferRemoveUnusedPrivateFnParam, """
             defmodule Solution do
               def find_lcs_length(first, second) do
                 compute_lcs(String.to_charlist(first), String.to_charlist(second), nil)
               end

               defp compute_lcs(chars_first, chars_second, _table)
                    when chars_first != [] and chars_second != [] do
                 if hd(chars_first) == hd(chars_second) do
                   compute_lcs(tl(chars_first), tl(chars_second), nil) + 1
                 else
                   max(
                     compute_lcs(tl(chars_first), chars_second, nil),
                     compute_lcs(chars_first, tl(chars_second), nil)
                   )
                 end
               end

               defp compute_lcs([], _second, _table), do: 0
               defp compute_lcs(_first, [], _table), do: 0
             end
             """)
    end

    test "unused param that is not underscore-prefixed" do
      assert flagged?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp helper(a, b, cache), do: a + b
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — should NOT be flagged
  # ═══════════════════════════════════════════════════════════════════

  describe "leaves good code alone" do
    test "all params are used" do
      assert clean?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute(x, y), do: x + y
             end
             """)
    end

    test "public function with unused param is not flagged" do
      assert clean?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               def compute(x, _unused), do: x + 1
             end
             """)
    end

    test "param used in body of at least one clause" do
      assert clean?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute([], table), do: table
               defp compute([_h | t], table), do: compute(t, table)
             end
             """)
    end

    test "underscore param is considered used when referenced" do
      assert clean?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute(x, _table), do: _table + x
             end
             """)
    end

    test "module with only public functions" do
      assert clean?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               def add(x, y), do: x + y
             end
             """)
    end
  end
end
