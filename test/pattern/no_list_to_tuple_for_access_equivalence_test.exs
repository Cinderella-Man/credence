defmodule Credence.Pattern.NoListToTupleForAccessEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoListToTupleForAccess

  # Firing snippets lifted from no_list_to_tuple_for_access_check_test.exs:
  #   defmodule PipedElem do
  #       def run(list) do
  #         t = List.to_tuple(list)
  #         t |> elem(0)
  #       end
  #     end
  #   defmodule DirectPipe do
  #       def run(list) do
  #         list |> List.to_tuple() |> elem(0)
  #       end
  #     end
  #   defmodule ScopeBug do
  #       def make(list) do
  #         t = List.to_tuple(list)
  #         t
  #       end
  #     
  #       def first(t) do
  #         elem(t, 0)
  #       end
  #     end

  test "no_list_to_tuple_for_access: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoListToTupleForAccess,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
