defmodule Credence.Pattern.PreferTupleDestructureAfterWithIndexEquivalenceTest do
  use Credence.RuleCase, async: true

  test "fix preserves behaviour" do
    # REPAIR (always-fails flavour): the "before" code uses a 2-arity fn with
    # Enum.map, which only ever calls its function with a single argument. There
    # is NO input that produces a valid result: a non-empty collection raises
    # BadArityError (the fn is invoked with one tuple arg), and an empty
    # collection raises FunctionClauseError before any element exists. So there
    # is no runtime behaviour to preserve; the fix is a correction.
    mark_equivalence_repair(
      "Before uses `fn row, index ->` (arity 2) with Enum.map, which always " <>
        "invokes its function with a single argument. Enum.with_index() emits " <>
        "{element, index} tuples, so a non-empty collection raises BadArityError " <>
        "and an empty collection raises FunctionClauseError — NO input avoids the " <>
        "crash. The fix destructures the tuple in the head: `fn {row, index} ->`."
    )
  end
end
