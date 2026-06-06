defmodule Credence.Pattern.NoUnlessElseEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoUnlessElse

  # Firing snippets lifted from no_unless_else_check_test.exs:
  #   def run(x) do
  #       unless x > 0 do
  #         :negative
  #       else
  #         :positive
  #       end
  #     end
  #   def run(list) do
  #       unless Enum.empty?(list) do
  #         first = hd(list)
  #         process(first)
  #       else
  #         log(:empty)
  #         :default
  #       end
  #     end
  #   def run(x, y) do
  #       unless x > 0 and y > 0 do
  #         :invalid
  #       else
  #         x + y
  #       end
  #     end

  test "no_unless_else: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoUnlessElse,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
