defmodule Credence.Pattern.NoEnumAtMidpointAccessEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoEnumAtMidpointAccess

  # Firing snippets lifted from no_enum_at_midpoint_access_check_test.exs:
  #   defmodule Search do
  #       def find(list, low, high) do
  #         mid = low + div(high - low, 2)
  #         Enum.at(list, mid)
  #       end
  #     end
  #   defmodule Search do
  #       def find(list, low, high) do
  #         mid = div(low + high, 2)
  #         Enum.at(list, mid)
  #       end
  #     end
  #   defmodule Search do
  #       def find(list, low, high) do
  #         mid = div(high - low, 2) + low
  #         Enum.at(list, mid)
  #       end
  #     end

  test "no_enum_at_midpoint_access: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoEnumAtMidpointAccess,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
