defmodule Credence.Pattern.PreferEnumReverseTwoEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.PreferEnumReverseTwo

  # Firing snippets lifted from prefer_enum_reverse_two_check_test.exs:
  #   defmodule OptimizationTarget do
  #       def merge(acc, tail) do
  #         Enum.reverse(acc) ++ tail
  #       end
  #     end
  #   defmodule GoodCode do
  #       def merge(acc, tail), do: Enum.reverse(acc, tail)
  #     end
  #   defmodule StandardConcatenation do
  #       def combine(a, b), do: a ++ b
  #     end

  test "prefer_enum_reverse_two: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: PreferEnumReverseTwo,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
