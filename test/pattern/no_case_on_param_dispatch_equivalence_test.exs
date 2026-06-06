defmodule Credence.Pattern.NoCaseOnParamDispatchEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoCaseOnParamDispatch

  # Firing snippets lifted from no_case_on_param_dispatch_check_test.exs:
  #   def run(x) do
  #       case x do
  #         0 -> :zero
  #         n -> {:ok, n}
  #       end
  #     end
  #   def pick_coins(coins) do
  #       case coins do
  #         [] -> 0
  #         [first] -> first
  #         [first, second] -> max(first, second)
  #         _ -> do_pick_coins(coins, 0, 0)
  #       end
  #     end
  #   def handle(msg) do
  #       case msg do
  #         %{type: :ping} -> :pong
  #         %{type: :data, payload: p} -> process(p)
  #         _ -> :unknown
  #       end
  #     end

  test "no_case_on_param_dispatch: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoCaseOnParamDispatch,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
