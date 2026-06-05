defmodule Credence.Pattern.PreferMapPutNewCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.PreferMapPutNew

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    PreferMapPutNew.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — must flag (pure key + value, exact-equivalent rewrite)
  # ═══════════════════════════════════════════════════════════════════

  describe "flags if Map.has_key? ... Map.put pattern" do
    test "standard if-has_key-else-put" do
      assert flagged?("""
             def run(map, key, val) do
               if Map.has_key?(map, key) do
                 map
               else
                 Map.put(map, key, val)
               end
             end
             """)
    end

    test "inside Enum.reduce" do
      assert flagged?("""
             def run(list) do
               Enum.reduce(list, %{}, fn {k, v}, acc ->
                 if Map.has_key?(acc, k) do
                   acc
                 else
                   Map.put(acc, k, v)
                 end
               end)
             end
             """)
    end

    test "with variable binding" do
      assert flagged?("""
             def run(map, key, val) do
               new_map =
                 if Map.has_key?(map, key) do
                   map
                 else
                   Map.put(map, key, val)
                 end

               new_map
             end
             """)
    end

    test "negated condition with swapped branches" do
      assert flagged?("""
             def run(map, key, val) do
               if !Map.has_key?(map, key) do
                 Map.put(map, key, val)
               else
                 map
               end
             end
             """)
    end

    test "unless variant" do
      assert flagged?("""
             def run(map, key, val) do
               unless Map.has_key?(map, key) do
                 Map.put(map, key, val)
               else
                 map
               end
             end
             """)
    end

    test "scalar literal value" do
      assert flagged?("""
             def run(map, key) do
               if Map.has_key?(map, key) do
                 map
               else
                 Map.put(map, key, 0)
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when already using Map.put_new" do
    test "Map.put_new directly" do
      assert clean?("""
             def run(map, key, val) do
               Map.put_new(map, key, val)
             end
             """)
    end
  end

  describe "does not flag when branches don't match" do
    test "key-exists branch does work instead of returning map" do
      assert clean?("""
             def run(map, key, val) do
               if Map.has_key?(map, key) do
                 Map.update!(map, key, &(&1 + 1))
               else
                 Map.put(map, key, val)
               end
             end
             """)
    end

    test "different map in put" do
      assert clean?("""
             def run(map_a, map_b, key, val) do
               if Map.has_key?(map_a, key) do
                 map_a
               else
                 Map.put(map_b, key, val)
               end
             end
             """)
    end

    test "different key in put" do
      assert clean?("""
             def run(map, key_a, key_b, val) do
               if Map.has_key?(map, key_a) do
                 map
               else
                 Map.put(map, key_b, val)
               end
             end
             """)
    end

    test "condition is not Map.has_key?" do
      assert clean?("""
             def run(map, key, val) do
               if map != nil do
                 map
               else
                 Map.put(%{}, key, val)
               end
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE (safety) — deliberately NOT flagged: the put_new rewrite
  # would NOT give the same answer on every input.
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when the rewrite would change behaviour" do
    # `Map.put_new/3` evaluates `value` eagerly; the `if` form evaluates it
    # only when the key is absent. An impure value (raise / side effect) would
    # behave differently when the key is present (`Map.put_new_lazy/3` exists
    # for exactly that reason).
    test "impure value (function call) is left alone" do
      assert clean?("""
             def run(map, key) do
               if Map.has_key?(map, key) do
                 map
               else
                 Map.put(map, key, compute_default())
               end
             end
             """)
    end

    test "impure value (raise) is left alone" do
      assert clean?("""
             def run(map, key) do
               if Map.has_key?(map, key) do
                 map
               else
                 Map.put(map, key, raise("boom"))
               end
             end
             """)
    end

    # The `if` form evaluates `key` twice (condition + Map.put); put_new once.
    test "impure key (function call) is left alone" do
      assert clean?("""
             def run(map) do
               if Map.has_key?(map, next_key()) do
                 map
               else
                 Map.put(map, next_key(), 0)
               end
             end
             """)
    end

    # `!!Map.has_key?` has even negation parity (≡ no negation): the do-branch
    # runs when the key is PRESENT, so this means "overwrite if present", which
    # is the opposite of put_new.
    test "double-negated condition is left alone" do
      assert clean?("""
             def run(map, key, val) do
               if !!Map.has_key?(map, key) do
                 Map.put(map, key, val)
               else
                 map
               end
             end
             """)
    end

    # `unless !Map.has_key?` ≡ `if Map.has_key?` → "overwrite if present".
    test "unless with negated condition is left alone" do
      assert clean?("""
             def run(map, key, val) do
               unless !Map.has_key?(map, key) do
                 Map.put(map, key, val)
               else
                 map
               end
             end
             """)
    end
  end
end
