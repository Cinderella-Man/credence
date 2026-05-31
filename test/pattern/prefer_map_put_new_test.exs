defmodule Credence.Pattern.PreferMapPutNewTest do
  use ExUnit.Case

  alias Credence.Pattern.PreferMapPutNew
  alias Credence.RuleHelpers

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    PreferMapPutNew.check(ast, [])
  end

  defp fix(code) do
    RuleHelpers.apply_rule_fix(PreferMapPutNew, code)
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — must flag
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
    test "both branches do work" do
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

    test "if has_key returns something other than map" do
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

    test "if has_key with different condition" do
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
  # FIX — auto-fix verification
  # ═══════════════════════════════════════════════════════════════════

  describe "fix" do
    test "replaces if-has_key-else-put with Map.put_new" do
      before = """
      def run(map, key, val) do
        new_map =
          if Map.has_key?(map, key) do
            map
          else
            Map.put(map, key, val)
          end
        new_map
      end
      """

      after_fix = fix(before)
      assert after_fix =~ "Map.put_new(map, key, val)"
      refute after_fix =~ "Map.has_key?"
    end

    test "replaces inside Enum.reduce" do
      before = """
      def run(list) do
        Enum.reduce(list, %{}, fn {k, v}, acc ->
          if Map.has_key?(acc, k) do
            acc
          else
            Map.put(acc, k, v)
          end
        end)
      end
      """

      after_fix = fix(before)
      assert after_fix =~ "Map.put_new(acc, k, v)"
      refute after_fix =~ "Map.has_key?"
    end

    test "replaces negated condition" do
      before = """
      def run(map, key, val) do
        if !Map.has_key?(map, key) do
          Map.put(map, key, val)
        else
          map
        end
      end
      """

      after_fix = fix(before)
      assert after_fix =~ "Map.put_new(map, key, val)"
      refute after_fix =~ "Map.has_key?"
    end

    test "replaces unless variant" do
      before = """
      def run(map, key, val) do
        unless Map.has_key?(map, key) do
          Map.put(map, key, val)
        else
          map
        end
      end
      """

      after_fix = fix(before)
      assert after_fix =~ "Map.put_new(map, key, val)"
      refute after_fix =~ "Map.has_key?"
    end
  end
end
