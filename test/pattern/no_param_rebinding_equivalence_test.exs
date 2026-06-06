defmodule Credence.Pattern.NoParamRebindingEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoParamRebinding

  # Firing snippets lifted from no_param_rebinding_check_test.exs:
  #   defmodule GoodReduce do
  #       def process(arr) do
  #         Enum.reduce(arr, {0, []}, fn x, {count, acc} ->
  #           new_count = count + 1
  #           new_acc = [x | acc]
  #           {new_count, new_acc}
  #         end)
  #       end
  #     end
  #   defmodule BadRebind do
  #       def process(arr) do
  #         Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
  #           q = :queue.in(x, q)
  #           count = count + 1
  #           {count, q}
  #         end)
  #       end
  #     end
  #   defmodule BadDestructure do
  #       def process(queue) do
  #         Enum.reduce(1..5, queue, fn _x, q ->
  #           {{:value, _h}, q} = :queue.out(q)
  #           q
  #         end)
  #       end
  #     end

  test "no_param_rebinding: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoParamRebinding,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
