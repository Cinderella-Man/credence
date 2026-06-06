defmodule Credence.Pattern.NoListPopAtForAccessEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoListPopAtForAccess

  # Firing snippets lifted from no_list_pop_at_for_access_check_test.exs:
  #   defmodule Bad do
  #       def pop_head(list) do
  #         list |> List.pop_at(0) |> elem(0)
  #       end
  #     end
  #   defmodule Bad do
  #       def pop_rest(list) do
  #         list |> List.pop_at(0) |> elem(1)
  #       end
  #     end
  #   defmodule Bad do
  #       def pop_head(list) do
  #         List.pop_at(list, 0) |> elem(0)
  #       end
  #     end

  test "no_list_pop_at_for_access: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoListPopAtForAccess,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
