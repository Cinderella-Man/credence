defmodule Credence.Pattern.NoMapThenFlattenTest do
  use ExUnit.Case

  alias Credence.Pattern.NoMapThenFlatten

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoMapThenFlatten.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags Enum.map piped to List.flatten" do
    test "basic piped form" do
      assert flagged?("""
             def pairs(list) do
               list
               |> Enum.map(fn x -> [x, x + 1] end)
               |> List.flatten()
             end
             """)
    end

    test "single-line piped form" do
      assert flagged?("""
             def flat(list), do: Enum.map(list, fn x -> [x, x + 1] end) |> List.flatten()
             """)
    end

    test "pipe chain with map then flatten then more steps" do
      assert flagged?("""
             def build(list) do
               list
               |> Enum.map(fn x -> [x, x * 2] end)
               |> List.flatten()
               |> Enum.join()
             end
             """)
    end

    test "map with 2-arg call piped to flatten" do
      assert flagged?("""
             def flat(list) do
               Enum.map(list, fn x -> [x, x + 1] end) |> List.flatten()
             end
             """)
    end
  end

  describe "flags List.flatten wrapping Enum.map" do
    test "basic nested form" do
      assert flagged?("""
             def pairs(list) do
               List.flatten(Enum.map(list, fn x -> [x, x + 1] end))
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag Enum.flat_map" do
    test "flat_map already used" do
      assert clean?("""
             def pairs(list) do
               Enum.flat_map(list, fn x -> [x, x + 1] end)
             end
             """)
    end
  end

  describe "does not flag List.flatten without Enum.map" do
    test "standalone List.flatten" do
      assert clean?("""
             def flat(list) do
               List.flatten(list)
             end
             """)
    end

    test "List.flatten of non-map expression" do
      assert clean?("""
             def flat(lists) do
               List.flatten(lists)
             end
             """)
    end
  end

  describe "does not flag Enum.map without List.flatten" do
    test "standalone map" do
      assert clean?("""
             def double(list) do
               Enum.map(list, fn x -> x * 2 end)
             end
             """)
    end

    test "map piped to join (handled by use_map_join)" do
      assert clean?("""
             def join(list) do
               list
               |> Enum.map(&to_string/1)
               |> Enum.join()
             end
             """)
    end
  end

  describe "does not flag flatten of pipe starting with non-map" do
    test "filter piped to flatten" do
      assert clean?("""
             def flat(list) do
               list
               |> Enum.filter(&(&1 > 0))
               |> List.flatten()
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX — auto-fix should work
  # ═══════════════════════════════════════════════════════════════════

  describe "fix: piped Enum.map |> List.flatten" do
    test "basic piped form is fixed to flat_map" do
      before = """
      def pairs(list) do
        list
        |> Enum.map(fn x -> [x, x + 1] end)
        |> List.flatten()
      end
      """

      after_ = apply_fix(before)
      assert after_ =~ "Enum.flat_map"
      refute after_ =~ "List.flatten"
    end

    test "pipe chain map |> flatten |> join is fixed" do
      before = """
      def build(list) do
        list
        |> Enum.map(fn x -> [x, x * 2] end)
        |> List.flatten()
        |> Enum.join()
      end
      """

      after_ = apply_fix(before)
      assert after_ =~ "Enum.flat_map"
      assert after_ =~ "Enum.join"
      refute after_ =~ "List.flatten"
    end
  end

  describe "fix: List.flatten(Enum.map(...))" do
    test "nested form is fixed to flat_map" do
      before = """
      def pairs(list) do
        List.flatten(Enum.map(list, fn x -> [x, x + 1] end))
      end
      """

      after_ = apply_fix(before)
      assert after_ =~ "Enum.flat_map"
      refute after_ =~ "List.flatten"
    end
  end

  defp apply_fix(code) do
    Credence.RuleHelpers.apply_rule_fix(Credence.Pattern.NoMapThenFlatten, code)
  end
end
