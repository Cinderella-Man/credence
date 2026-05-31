defmodule Credence.Pattern.NoReduceForPartitionTest do
  use ExUnit.Case

  alias Credence.Pattern.NoReduceForPartition

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoReduceForPartition.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []


  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag
  # ═══════════════════════════════════════════════════════════════════

  describe "flags reduce-based partition with {[], []} accumulator" do
    test "basic even/odd partition with guard" do
      assert flagged?("""
             def separate_parity(list) do
               {evens, odds} =
                 Enum.reduce(list, {[], []}, fn
                   num, {evens, odds} when rem(num, 2) == 0 ->
                     {[num | evens], odds}
                   num, {evens, odds} ->
                     {evens, [num | odds]}
                 end)

               {Enum.reverse(evens), Enum.reverse(odds)}
             end
             """)
    end

    test "partition with negated guard on first clause" do
      assert flagged?("""
             def split(list) do
               {pos, neg} =
                 Enum.reduce(list, {[], []}, fn
                   x, {pos, neg} when x >= 0 -> {[x | pos], neg}
                   x, {pos, neg} -> {pos, [x | neg]}
                 end)
               {Enum.reverse(pos), Enum.reverse(neg)}
             end
             """)
    end

    test "piped into Enum.reduce" do
      assert flagged?("""
             def partition(items) do
               {a, b} =
                 items
                 |> Enum.reduce({[], []}, fn
                   item, {a, b} when is_atom(item) -> {[item | a], b}
                   item, {a, b} -> {a, [item | b]}
                 end)

               {Enum.reverse(a), Enum.reverse(b)}
             end
             """)
    end

    test "guard on second clause instead of first" do
      assert flagged?("""
             def classify(list) do
               {good, bad} =
                 Enum.reduce(list, {[], []}, fn
                   x, {good, bad} -> {good, [x | bad]}
                   x, {good, bad} when x > 0 -> {[x | good], bad}
                 end)
               {Enum.reverse(good), Enum.reverse(bad)}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag good code" do
    test "Enum.split_with is clean" do
      assert clean?("""
             def separate_parity(list) do
               Enum.split_with(list, &(rem(&1, 2) == 0))
             end
             """)
    end

    test "reduce with non-empty initial accumulator" do
      assert clean?("""
             def build(list) do
               Enum.reduce(list, {[0], [0]}, fn
                 x, {evens, odds} when rem(x, 2) == 0 -> {[x | evens], odds}
                 x, {evens, odds} -> {evens, [x | odds]}
               end)
             end
             """)
    end

    test "reduce with single clause (not a partition)" do
      assert clean?("""
             def collect(list) do
               Enum.reduce(list, {[], []}, fn
                 x, {evens, odds} -> {[x | evens], [x | odds]}
               end)
             end
             """)
    end

    test "reduce with three clauses (three-way partition)" do
      assert clean?("""
             def classify(list) do
               Enum.reduce(list, {[], [], []}, fn
                 x, {pos, neg, zero} when x > 0 -> {[x | pos], neg, zero}
                 x, {pos, neg, zero} when x < 0 -> {pos, [x | neg], zero}
                 x, {pos, neg, zero} -> {pos, neg, [x | zero]}
               end)
             end
             """)
    end

    test "reduce that transforms elements while partitioning" do
      assert clean?("""
             def split_transform(list) do
               Enum.reduce(list, {[], []}, fn
                 x, {evens, odds} when rem(x, 2) == 0 -> {[x * 2 | evens], odds}
                 x, {evens, odds} -> {evens, [x * 3 | odds]}
               end)
             end
             """)
    end

    test "reduce with Map accumulator" do
      assert clean?("""
             def group(list) do
               Enum.reduce(list, %{yes: [], no: []}, fn
                 x, acc when x > 0 -> %{acc | yes: [x | acc.yes]}
                 x, acc -> %{acc | no: [x | acc.no]}
               end)
             end
             """)
    end

    test "Enum.split_with piped" do
      assert clean?"""
             def split(list) do
               list |> Enum.split_with(&(rem(&1, 2) == 0))
             end
             """
    end
  end
end
