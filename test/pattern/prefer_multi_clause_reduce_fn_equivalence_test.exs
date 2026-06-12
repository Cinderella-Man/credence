defmodule Credence.Pattern.PreferMultiClauseReduceFnEquivalenceTest do
  @moduledoc """
  Tier 2 (module-level). The majority_element Boyer-Moore voting algorithm
  is compiled as a module; before/after must agree on every input.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferMultiClauseReduceFn

  test "majority_element fix preserves behaviour" do
    before = """
    defmodule MajorityBefore do
      def majority_element(list) when is_list(list) do
        {majority, _count} =
          Enum.reduce(list, {nil, 0}, fn element, {candidate, count} ->
            if count == 0 do
              {element, 1}
            else
              if element == candidate do
                {candidate, count + 1}
              else
                {candidate, count - 1}
              end
            end
          end)
        majority
      end
    end
    """

    assert_equivalent_module(before,
      rule: PreferMultiClauseReduceFn,
      call: {:majority_element, 1},
      inputs: [
        [1, 1, 2, 1, 2],
        [3, 3, 3, 4, 4],
        [5],
        Enum.map(1..20, fn _ -> 7 end) ++ [8, 8, 8]
      ]
    )
  end
end
