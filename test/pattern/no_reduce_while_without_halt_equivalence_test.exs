defmodule Credence.Pattern.NoReduceWhileWithoutHaltEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoReduceWhileWithoutHalt

  # Firing snippets lifted from no_reduce_while_without_halt_check_test.exs:
  #   defmodule Good do
  #       def total(list) do
  #         Enum.reduce(list, 0, fn x, acc -> acc + x end)
  #       end
  #     end
  #   defmodule Good do
  #       def find_negative(list) do
  #         Enum.reduce_while(list, 0, fn x, acc ->
  #           if x < 0, do: {:halt, acc}, else: {:cont, acc + x}
  #         end)
  #       end
  #     end
  #   defmodule Good do
  #       def process(list) do
  #         Enum.reduce_while(list, 0, fn
  #           :stop, acc -> {:halt, acc}
  #           x, acc -> {:cont, acc + x}
  #         end)
  #       end
  #     end

  test "no_reduce_while_without_halt: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoReduceWhileWithoutHalt,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
