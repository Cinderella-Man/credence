defmodule Credence.Pattern.PreferStdlibGcdEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Hand-rolled Euclidean GCD is replaced by `Integer.gcd/2`.
  Both implement the same algorithm (Euclid's), so the LCM computed via
  `div(a * b, gcd(a, b))` is identical for every positive-integer pair.

  The fixture is guarded on positive inputs (`first > 0 and second > 0`) on
  purpose: `Integer.gcd/2` is always non-negative while the hand-rolled base case
  returns `a` unchanged, so equivalence holds only on GCD's natural non-negative
  domain (see the rule's `@moduledoc`).
  """

  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferStdlibGcd

  test "fix preserves behaviour for all positive integer pairs" do
    assert_equivalent_module(
      """
      defmodule LcmTest do
        def smallest_common_mult(first, second) when first > 0 and second > 0 do
          div(first * second, gcd(first, second))
        end

        defp gcd(a, 0), do: a
        defp gcd(a, b), do: gcd(b, rem(a, b))
      end
      """,
      rule: PreferStdlibGcd,
      call: {:smallest_common_mult, 2},
      inputs: [{1, 1}, {2, 3}, {6, 4}, {12, 8}, {7, 5}, {100, 75}, {17, 13}]
    )
  end
end
