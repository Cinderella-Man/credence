defmodule Credence.Pattern.NoLengthGuardToPatternEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). Exact-length guards become exact-length list patterns,
  which reject the same improper lists as `length/1` in a guard.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoLengthGuardToPattern

  @before """
  defmodule Bad do
    def process(list) when length(list) == 2, do: Enum.sum(list)
    def process(_), do: 0
  end
  """

  test "length(list) == 2 guard preserves dispatch including improper lists" do
    assert_equivalent_module(@before,
      rule: NoLengthGuardToPattern,
      call: {:process, 1},
      inputs: [[], [5], [1, 2], [1, 2, 3], [1 | 2]]
    )
  end
end
