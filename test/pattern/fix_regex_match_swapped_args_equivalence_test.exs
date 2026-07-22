defmodule Credence.Pattern.FixRegexMatchSwappedArgsEquivalenceTest do
  use Credence.RuleCase, async: true

  test "fix is a repair (before crashes on every input)" do
    # The rule fires only when the left side of `=~` is provably never a
    # binary: a ~r sigil literal, or a module attribute whose every `@attr`
    # assignment in the file is a ~r literal (with no
    # Module.put_attribute/register_attribute anywhere, and never inside a
    # quote block). Every clause of `Kernel.=~/2` requires `is_binary(left)`,
    # so the "before" raises FunctionClauseError on every input — the swap is
    # a repair, not a behaviour-preserving rewrite.
    mark_equivalence_repair(
      "left side is provably a regex (or nil/list from a regex-only attribute), " <>
        "never a binary — Kernel.=~/2 requires is_binary(left), so the before " <>
        "raises FunctionClauseError on every input"
    )
  end
end
