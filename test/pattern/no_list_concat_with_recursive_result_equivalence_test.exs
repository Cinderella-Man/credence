defmodule Credence.Pattern.NoListConcatWithRecursiveResultEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoListConcatWithRecursiveResult

  # Firing snippets lifted from no_list_concat_with_recursive_result_check_test.exs:
  #   defmodule Bad do
  #       def build([]), do: []
  #     
  #       def build([h | t]) do
  #         [h] ++ build(t)
  #       end
  #     end
  #   defmodule Bad do
  #       def pre([]), do: []
  #       def pre([h | t]), do: [h, h * 2] ++ pre(t)
  #     end
  #   defmodule Bad do
  #       def build([]), do: []
  #     
  #       def build([h | t]) do
  #         rest = build(t)
  #         [h] ++ rest
  #       end
  #     end

  test "no_list_concat_with_recursive_result: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoListConcatWithRecursiveResult,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
