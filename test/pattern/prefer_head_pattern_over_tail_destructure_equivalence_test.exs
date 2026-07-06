defmodule Credence.Pattern.PreferHeadPatternOverTailDestructureEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). The rule combines a cons pattern's tail destructuring
  into the function head. The fix is behaviour-preserving because the same
  variables are bound to the same values — only the binding location changes.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferHeadPatternOverTailDestructure

  @before """
  defmodule Solution do
    def check([current_row | remaining_rows]) do
      [next_row | _] = remaining_rows
      tl(next_row)
      {current_row, next_row}
    end
  end
  """

  test "fix preserves behaviour: combining cons + destructured tail" do
    assert_equivalent_module(@before,
      rule: PreferHeadPatternOverTailDestructure,
      call: {:check, 1},
      inputs: [
        [[1, 2, 3], [4, 5, 6], [7, 8, 9]],
        [[:a, :b], [:c, :d]],
        [["x", "y", "z"], ["w"]]
      ]
    )
  end
end
