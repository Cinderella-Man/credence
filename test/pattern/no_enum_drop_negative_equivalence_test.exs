defmodule Credence.Pattern.NoEnumDropNegativeEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoEnumDropNegative

  # Firing snippets lifted from no_enum_drop_negative_check_test.exs:
  #   defmodule BadDrop do
  #       def remove_last(list) do
  #         Enum.drop(list, -1)
  #       end
  #     end
  #   defmodule BadPiped do
  #       def remove_last(list) do
  #         list |> Enum.drop(-1)
  #       end
  #     end
  #   defmodule MultipleBad do
  #       def process(list) do
  #         a = Enum.drop(list, -1)
  #         b = Enum.drop(list, -2)
  #         {a, b}
  #       end
  #     end

  test "no_enum_drop_negative: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoEnumDropNegative,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
