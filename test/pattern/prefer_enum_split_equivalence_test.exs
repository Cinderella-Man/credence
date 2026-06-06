defmodule Credence.Pattern.PreferEnumSplitEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.PreferEnumSplit

  # Firing snippets lifted from prefer_enum_split_check_test.exs:
  #   defmodule Bad do
  #       def halves(list) do
  #         first = Enum.take(list, 3)
  #         rest = Enum.drop(list, 3)
  #         {first, rest}
  #       end
  #     end
  #   defmodule Bad do
  #       def halves(list) do
  #         a = Enum.take(list, 0)
  #         b = Enum.drop(list, 0)
  #         {a, b}
  #       end
  #     end
  #   defmodule LineCheck do
  #       def halves(list) do
  #         first = Enum.take(list, 3)
  #         rest = Enum.drop(list, 3)
  #         {first, rest}
  #       end
  #     end

  test "prefer_enum_split: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: PreferEnumSplit,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
