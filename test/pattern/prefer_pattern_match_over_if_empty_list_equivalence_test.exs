defmodule Credence.Pattern.PreferPatternMatchOverIfEmptyListEquivalenceTest do
  @moduledoc """
  Tier 2 (module-level). Rewrites `def process(list) do if list == [] do 0 else
  Enum.sum(list) end end` to multi-clause `def process([]), do: 0 / def
  process(list) do Enum.sum(list) end`. Empty-list and non-empty branches
  produce distinct outcomes (0 vs positive sum), so the inputs discriminate.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferPatternMatchOverIfEmptyList

  test "fix preserves behaviour for empty and non-empty lists" do
    assert_equivalent_module(
      """
      defmodule Solution do
        @spec process(list()) :: non_neg_integer()
        def process(list) do
          if list == [] do
            0
          else
            Enum.sum(list)
          end
        end
      end
      """,
      rule: PreferPatternMatchOverIfEmptyList,
      call: {:process, 1},
      inputs: [[], [1], [1, 2, 3], [-1, 0, 1], Enum.to_list(1..50)]
    )
  end

  test "guarded Enum.empty? form preserves behaviour (is_list guard restricts to lists)" do
    assert_equivalent_module(
      """
      defmodule Solution do
        def process(list) when is_list(list) do
          if Enum.empty?(list) do
            0
          else
            Enum.sum(list)
          end
        end
      end
      """,
      rule: PreferPatternMatchOverIfEmptyList,
      call: {:process, 1},
      inputs: [[], [1], [1, 2, 3], [-1, 0, 1], Enum.to_list(1..50)]
    )
  end
end
