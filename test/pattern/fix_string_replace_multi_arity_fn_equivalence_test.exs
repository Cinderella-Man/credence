defmodule Credence.Pattern.FixStringReplaceMultiArityFnEquivalenceTest do
  use Credence.RuleCase, async: true

  test "fix preserves behaviour" do
    # This is a REPAIR: both the before (with []) and the after (without [])
    # crash at runtime because String.replace/4 only accepts arity-1 functions.
    # The fix removes the spurious [], which is a step toward correctness even
    # though the arity-2 issue remains. Both sides raise FunctionClauseError.
    mark_equivalence_repair(
      "String.replace/4 with arity-2 fn crashes on every input; " <>
        "removing [] is a step toward correctness but /3 also rejects arity-2"
    )
  end
end
