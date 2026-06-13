defmodule Credence.Pattern.PreferRemoveUnusedPrivateFnParamCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferRemoveUnusedPrivateFnParam

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should be flagged (unused AND not underscored)
  # ═══════════════════════════════════════════════════════════════════

  describe "flags unused, un-underscored private function parameters" do
    test "single clause with non-underscore unused param" do
      assert flagged?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute(x, table), do: x + 1
             end
             """)
    end

    test "multi-clause function with non-underscore unused param in all clauses" do
      assert flagged?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute([], table), do: 0
               defp compute([h | t], table), do: h + compute(t, nil)
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

    test "underscore-prefixed unused param is left alone (intentional marker)" do
      assert clean?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute(x, _unused), do: x + 1
             end
             """)
    end

    test "underscore-prefixed unused param across all clauses is left alone" do
      assert clean?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp compute([], _table), do: 0
               defp compute([h | t], _table), do: h + compute(t, nil)
             end
             """)
    end

    test "param reused in another argument's pattern (non-linear match) is left alone" do
      # `pk` at position 0 never appears in a body/guard, but position 1's
      # pattern `[pk | rest]` requires arg0 == hd(arg1). Removing it would change
      # what the clause matches.
      assert clean?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               defp check(pk, [pk | rest]), do: rest
               defp check(pk, []), do: []
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

    test "module with only public functions" do
      assert clean?(PreferRemoveUnusedPrivateFnParam, """
             defmodule M do
               def add(x, y), do: x + y
             end
             """)
    end
  end
end
