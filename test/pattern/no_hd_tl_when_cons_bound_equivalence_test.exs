defmodule Credence.Pattern.NoHdTlWhenConsBoundEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoHdTlWhenConsBound

  # Firing snippets lifted from no_hd_tl_when_cons_bound_check_test.exs:
  #   defmodule Bad do
  #       def first(list = [_ | _]), do: hd(list)
  #     end
  #   defmodule Bad do
  #       def rest(list = [_ | _]), do: tl(list)
  #     end
  #   defmodule Bad do
  #       def split(list = [_ | _]), do: {hd(list), tl(list)}
  #     end

  test "no_hd_tl_when_cons_bound: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoHdTlWhenConsBound,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
