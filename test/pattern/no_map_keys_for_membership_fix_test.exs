defmodule Credence.Pattern.NoMapKeysForMembershipFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoMapKeysForMembership

  test "x not in Map.keys(m) → not Map.has_key?(m, x) inside a capture" do
    code = """
    defmodule TestMod do
      def filter_visited(queue, visited) do
        Enum.filter(queue, &(&1 not in Map.keys(visited)))
      end
    end
    """

    expected = """
    defmodule TestMod do
      def filter_visited(queue, visited) do
        Enum.filter(queue, &(not Map.has_key?(visited, &1)))
      end
    end
    """

    confirm_fix(fix(NoMapKeysForMembership, code), expected)
  end

  test "x in Map.keys(m) → Map.has_key?(m, x) inside an if" do
    code = """
    defmodule TestMod do
      def lookup(key, map) do
        if key in Map.keys(map), do: present, else: absent
      end
    end
    """

    expected = """
    defmodule TestMod do
      def lookup(key, map) do
        if Map.has_key?(map, key), do: present, else: absent
      end
    end
    """

    confirm_fix(fix(NoMapKeysForMembership, code), expected)
  end

  test "no-op when left operand is side-effecting (function call)" do
    code = """
    defmodule TestMod do
      def known?(map) do
        compute_key(map) in Map.keys(map)
      end
    end
    """

    confirm_fix(fix(NoMapKeysForMembership, code), code)
  end

  # ── An EMBEDDABLE fixture, for `test/dsl_macro_protection_test.exs`. ──
  #
  # This rule declares `unsafe_in_dsl/0`, and that gate proves the declaration
  # actually protects the macro by wrapping a fixture in an `expr(...)` or a
  # `defn` body and requiring the fix to be dropped. It can only wrap a BARE
  # EXPRESSION, and every other fixture in this file is a whole `defmodule` — so
  # without this one the gate has nothing to embed and reports the rule as
  # having vacuous coverage. It pins the ordinary rewrite too, so it is a real
  # test rather than a fixture parked for another file to find.
  describe "embeddable fixture (DSL macro protection)" do
    test "the bare expression form rewrites" do
      input = "k in Map.keys(m)"

      expected = "Map.has_key?(m, k)"

      confirm_fix(fix(Credence.Pattern.NoMapKeysForMembership, input), expected)
    end
  end
end
