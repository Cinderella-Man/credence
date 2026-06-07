defmodule Credence.Pattern.NoDestructureReconstructEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A `case` clause that destructures a list into `[p1, p2, p3, p4]`
  and then rebuilds the same `[p1, p2, p3, p4]` is rewritten to bind the whole list
  (`[_, _, _, _] = items`) and reuse it. Same elements, same order — the reconstructed
  list is identical to the matched one.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoDestructureReconstruct

  @before """
  defmodule Bad do
    def check(ip) do
      case String.split(ip, ".") do
        [p1, p2, p3, p4] -> Enum.all?([p1, p2, p3, p4], fn p -> p != "" end)
        _ -> false
      end
    end
  end
  """

  test "destructure-then-reconstruct → bind-and-reuse preserves the result" do
    assert_equivalent_module(@before,
      rule: NoDestructureReconstruct,
      call: {:check, 1},
      inputs: ["1.2.3.4", "a.b.c.d", "a.b", "1..3.4", "", "1.2.3.4.5"]
    )
  end
end
