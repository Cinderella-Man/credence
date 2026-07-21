defmodule Credence.StdlibSortDescSentinelTest do
  use ExUnit.Case, async: true

  # `no_sort_then_reverse` and `no_double_sort_same_list` rewrite
  # `Enum.sort(l) |> Enum.reverse()` into `Enum.sort(l, :desc)`. On Elixir
  # 1.20 that is `===`-exact for every input — `:desc` reverses tie groups
  # exactly as reverse-of-ascending does (brute-forced over 625 tie-heavy
  # int/float lists, docs/14 B.11) — but the stdlib docs do not clearly
  # promise `sort(:desc)`'s tie ordering. If an Elixir upgrade turns this
  # test red, those two rules are no longer behaviour-preserving: fix or
  # retire the rules before touching this test.
  test "Enum.sort/2 :desc orders tie groups as reverse-of-ascending" do
    assert Enum.sort([1, 1.0], :desc) === [1.0, 1]

    reversed_asc = Enum.reverse(Enum.sort([1, 1.0]))
    assert reversed_asc === Enum.sort([1, 1.0], :desc)

    assert Enum.sort([1, 2, 2.0], :desc) === [2.0, 2, 1]

    # Tie groups are REVERSED relative to input order (not kept stable):
    # ascending is stable ([1.0, 1, ...] stays), reversing flips each group.
    input = [1.0, 1, 2, 2.0]
    assert Enum.sort(input, :desc) === [2.0, 2, 1, 1.0]
    assert Enum.sort(input, :desc) === Enum.reverse(Enum.sort(input))
  end
end
