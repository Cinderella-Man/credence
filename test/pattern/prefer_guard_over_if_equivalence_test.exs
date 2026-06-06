defmodule Credence.Pattern.PreferGuardOverIfEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferGuardOverIf

  # Firing snippets lifted from prefer_guard_over_if_check_test.exs:
  #   defp accumulate_run(last_val, [head | tail] = list, current_run) do
  #       if head > last_val do
  #         accumulate_run(head, tail, [head | current_run])
  #       else
  #         {Enum.reverse(current_run), list}
  #       end
  #     end
  #   defp handle(x, acc) do
  #       if x == 0 do
  #         acc
  #       else
  #         [x | acc]
  #       end
  #     end
  #   defp process(val, default) do
  #       if is_nil(val) do
  #         default
  #       else
  #         val
  #       end
  #     end

  test "prefer_guard_over_if: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: PreferGuardOverIf,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
