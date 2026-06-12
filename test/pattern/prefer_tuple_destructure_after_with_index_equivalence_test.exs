defmodule Credence.Pattern.PreferTupleDestructureAfterWithIndexEquivalenceTest do
  use Credence.RuleCase, async: true

  test "fix preserves behaviour" do
    # REPAIR: the "before" code uses a 2-arity fn with Enum.map, which expects
    # arity 1. Every input raises BadArityError because Enum.with_index()
    # emits {element, index} tuples and Enum.map passes them as a single arg.
    # BadArityError 40/40, minimal_set=none.
    mark_equivalence_repair(
      "Before uses `fn row, index ->` (arity 2) with Enum.map, which requires " <>
        "arity 1. Enum.with_index() emits {element, index} tuples as a single " <>
        "argument, so every input raises BadArityError. The fix destructures the " <>
        "tuple: `fn {row, index} ->`."
    )
  end
end
