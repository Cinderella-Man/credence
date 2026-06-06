defmodule Credence.Pattern.NoListDeleteAtWithLengthEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoListDeleteAtWithLength

  # Firing snippets lifted from no_list_delete_at_with_length_check_test.exs:
  #   defmodule M do
  #       def drop_last(list) do
  #         List.delete_at(list, length(list) - 1)
  #       end
  #     end
  #   defmodule M do
  #       def drop_idx(list, idx) do
  #         List.delete_at(list, idx)
  #       end
  #     end
  #   defmodule M do
  #       def drop(list) do
  #         List.delete_at(list, length(list) - 2)
  #       end
  #     end

  test "no_list_delete_at_with_length: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoListDeleteAtWithLength,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
