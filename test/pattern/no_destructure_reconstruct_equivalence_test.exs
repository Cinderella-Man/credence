defmodule Credence.Pattern.NoDestructureReconstructEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoDestructureReconstruct

  # Firing snippets lifted from no_destructure_reconstruct_check_test.exs:
  #   defmodule Bad do
  #       def check(ip) do
  #         case String.split(ip, ".") do
  #           [p1, p2, p3, p4] ->
  #             Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
  #           _ ->
  #             false
  #         end
  #       end
  #     end
  #   defmodule Bad do
  #       def swap(input) do
  #         case String.split(input, ":") do
  #           [a, b] -> Enum.join([a, b], "-")
  #           _ -> input
  #         end
  #       end
  #     end
  #   defmodule Bad do
  #       def process(data) do
  #         case data do
  #           [x, y, z] -> Enum.map([x, y, z], &to_string/1)
  #         end
  #       end
  #     end

  test "no_destructure_reconstruct: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoDestructureReconstruct,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
