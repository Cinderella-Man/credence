defmodule Credence.Pattern.NoIdentityEnumMapEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), unconditional — no assumptions.

  `Enum.map(enum, & &1)` → `Enum.to_list(enum)` has the identical contract to the
  original on EVERY input kind, which is precisely why the rewrite targets
  `Enum.to_list/1` rather than the bare argument:

    * lists / ranges / maps  → both produce the same list,
    * non-enumerables (a bare string, an integer) → both raise
      `Protocol.UndefinedError` (same exception class).

  So the suite deliberately feeds the string dimension alongside the list one:
  the bare-argument rewrite (`→ enum`) would DIVERGE on `""` (returns it instead
  of raising); `Enum.to_list/1` does not.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceInputs, as: B
  alias Credence.Pattern.NoIdentityEnumMap

  test "Enum.map(enum, & &1) → Enum.to_list(enum) — lists return, non-enumerables raise alike" do
    # Lists/integers produce values; the strings all raise. Mixing both
    # dimensions gives the suite varied outcomes to discriminate against AND
    # proves the cross-dimension safety that motivated `Enum.to_list/1`.
    assert_equivalent(
      """
      Enum.map(enum, & &1)
      """,
      rule: NoIdentityEnumMap,
      vars: [:enum],
      inputs: B.term_lists() ++ B.signed_integers() ++ B.unicode_strings()
    )
  end

  test "the bare-argument rewrite would diverge here — to_list keeps the raise contract" do
    # Every non-enumerable raises `Protocol.UndefinedError` on BOTH sides; the
    # output is constant by design (that is the contract under test), hence
    # `allow_constant_output`. A `→ enum` rule would return "" instead and fail.
    assert_equivalent(
      """
      Enum.map(enum, fn x -> x end)
      """,
      rule: NoIdentityEnumMap,
      vars: [:enum],
      inputs: B.unicode_strings(),
      allow_constant_output: true
    )
  end
end
