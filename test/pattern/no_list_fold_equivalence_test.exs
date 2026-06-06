defmodule Credence.Pattern.NoListFoldEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoListFold

  # Firing snippets lifted from no_list_fold_check_test.exs:
  #   List.foldl(list, 0, fn x, acc -> acc + x end)
  #   List.foldr(list, [], fn x, acc -> [x | acc] end)
  #   Enum.reduce(list, 0, fn x, acc -> acc + x end)

  test "no_list_fold: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoListFold,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
