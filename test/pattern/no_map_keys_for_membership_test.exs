defmodule Credence.Pattern.NoMapKeysForMembershipTest do
  use ExUnit.Case

  alias Credence.Pattern.NoMapKeysForMembership

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoMapKeysForMembership.check(ast, [])
  end

  defp apply_fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoMapKeysForMembership, code)
  end

  # ═══════════════════════════════════════════════════════════════════
  # SHOULD fire
  # ═══════════════════════════════════════════════════════════════════

  describe "check: flags x not in Map.keys(m)" do
    test "inside a capture predicate" do
      code = """
      defmodule TestMod do
        def filter_visited(queue, visited) do
          Enum.filter(queue, &(&1 not in Map.keys(visited)))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_map_keys_for_membership
    end

    test "inside an fn predicate" do
      code = """
      defmodule TestMod do
        def filter_visited(queue, visited) do
          Enum.filter(queue, fn pos -> pos not in Map.keys(visited) end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "inside an if expression" do
      code = """
      defmodule TestMod do
        def check_key(key, cache) do
          if key not in Map.keys(cache), do: compute(key), else: cached
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end
  end

  describe "check: flags x in Map.keys(m)" do
    test "inside a capture predicate" do
      code = """
      defmodule TestMod do
        def keep_allowed(enum, allowed) do
          Enum.filter(enum, &(&1 in Map.keys(allowed)))
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_map_keys_for_membership
    end

    test "inside an if expression" do
      code = """
      defmodule TestMod do
        def lookup(key, map) do
          if key in Map.keys(map), do: Map.get(map, key), else: nil
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # should NOT fire
  # ═══════════════════════════════════════════════════════════════════

  describe "check: does not flag" do
    test "x in a plain list" do
      code = """
      defmodule TestMod do
        def filter(queue, visited_list) do
          Enum.filter(queue, &(&1 not in visited_list))
        end
      end
      """

      assert check(code) == []
    end

    test "Map.keys in a non-membership context" do
      code = """
      defmodule TestMod do
        def keys(map) do
          Map.keys(map)
        end
      end
      """

      assert check(code) == []
    end

    test "Map.has_key? already used" do
      code = """
      defmodule TestMod do
        def filter(queue, visited) do
          Enum.reject(queue, &Map.has_key?(visited, &1))
        end
      end
      """

      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Auto-fix
  # ═══════════════════════════════════════════════════════════════════

  describe "fix" do
    test "x not in Map.keys(m) → not Map.has_key?(m, x)" do
      before = """
      defmodule TestMod do
        def filter_visited(queue, visited) do
          Enum.filter(queue, &(&1 not in Map.keys(visited)))
        end
      end
      """

      after_ = apply_fix(before)
      assert after_ =~ "not Map.has_key?"
      assert after_ =~ "visited, &1"
      refute after_ =~ "Map.keys"
    end

    test "x in Map.keys(m) → Map.has_key?(m, x)" do
      before = """
      defmodule TestMod do
        def lookup(key, map) do
          if key in Map.keys(map), do: present, else: absent
        end
      end
      """

      after_ = apply_fix(before)
      assert after_ =~ "Map.has_key?"
      assert after_ =~ "map, key"
      refute after_ =~ "Map.keys"
    end
  end
end
