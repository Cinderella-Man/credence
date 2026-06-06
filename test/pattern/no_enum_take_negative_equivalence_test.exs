defmodule Credence.Pattern.NoEnumTakeNegativeEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoEnumTakeNegative

  # Firing snippets lifted from no_enum_take_negative_check_test.exs:
  #   defmodule BadTake do
  #       def last_three(list) do
  #         sorted = Enum.sort(list)
  #         Enum.take(sorted, -3)
  #       end
  #     end
  #   defmodule BadPiped do
  #       def last_three(list) do
  #         list |> Enum.sort() |> Enum.take(-3)
  #       end
  #     end
  #   defmodule BadOne do
  #       def last(list), do: Enum.take(list, -1)
  #     end

  test "no_enum_take_negative: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoEnumTakeNegative,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
