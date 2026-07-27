defmodule Credence.Pattern.FixRegexMatchSwappedArgsEquivalenceTest do
  use Credence.RuleCase, async: true

  test "fix is a repair (before crashes on every input)" do
    # `~r/abc/ =~ x` always raises `FunctionClauseError` because
    # `Kernel.=~/2` requires `is_binary(left)`. The fix swaps the
    # operands, which is a repair, not a behaviour-preserving rewrite.
    mark_equivalence_repair(
      "regex on the left of =~ always raises FunctionClauseError — " <>
        "Kernel.=~/2 requires is_binary(left)"
    )
  end
end
