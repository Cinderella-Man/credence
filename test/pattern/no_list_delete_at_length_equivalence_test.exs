defmodule Credence.Pattern.NoListDeleteAtLengthEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoListDeleteAtLength

  # Firing snippets lifted from no_list_delete_at_length_check_test.exs:
  #   List.delete_at(list, length(list) - 1)
  #   List.delete_at(list, Kernel.length(list) - 1)
  #   defmodule Solution do
  #       def swap_head_tail(list) do
  #         [head | tail] = list
  #         last = List.last(tail)
  #         middle = List.delete_at(tail, length(tail) - 1)
  #         [last | middle] ++ [head]
  #       end
  #     end

  test "no_list_delete_at_length: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoListDeleteAtLength,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
