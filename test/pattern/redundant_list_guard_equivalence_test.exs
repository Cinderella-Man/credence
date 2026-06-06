defmodule Credence.Pattern.RedundantListGuardEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call), assumption-gated rule.

  The fix drops `when is_list(tail)` from a cons-head clause. Under the rule's
  declared `proper_lists` promise the tail is always a list, so the guard never
  changes which clause matches and the fix is behaviour-preserving. Outside the
  promise — on an improper list like `[1 | 2]` — it diverges, which is exactly
  why the rule carries the switch.

  This mirrors the `no_codepoint_string_reverse` dual exemplar: pass within the
  assumption's domain, and prove the suite *catches* the divergence outside it.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.RedundantListGuard

  @before """
  defmodule Bad do
    def f([first | rest]) when is_list(rest), do: {:matched, first, rest}
    def f(_), do: :fallthrough
  end
  """

  test "preserves f/1 behaviour over PROPER lists (in-assumption domain)" do
    assert_equivalent_module(@before,
      rule: RedundantListGuard,
      call: {:f, 1},
      inputs: [[], [1], [1, 2, 3], [:a, :b], [nil, false], Enum.to_list(1..50)]
    )
  end

  test "DIVERGES on an improper list — the harness flags it (why proper_lists exists)" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_equivalent_module(@before,
        rule: RedundantListGuard,
        call: {:f, 1},
        # [1 | 2] routes to :fallthrough with the guard, {:matched,1,2} without
        inputs: [[1, 2], [1 | 2], [], :notalist]
      )
    end
  end
end
