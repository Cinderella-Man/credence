defmodule Credence.Pattern.NoManualListLastEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualListLast

  # Firing snippets lifted from no_manual_list_last_check_test.exs:
  #   defmodule Bad do
  #       defp get_last_element([val]), do: val
  #       defp get_last_element([_ | rest]), do: get_last_element(rest)
  #     end
  #   defmodule Bad do
  #       defp last_item([x]), do: x
  #       defp last_item([_ | t]), do: last_item(t)
  #     end
  #   defmodule Bad do
  #       defp tail_val([v]), do: v
  #       defp tail_val([_head | rest]), do: tail_val(rest)
  #     end

  test "no_manual_list_last: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoManualListLast,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
