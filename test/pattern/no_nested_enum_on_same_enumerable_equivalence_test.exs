defmodule Credence.Pattern.NoNestedEnumOnSameEnumerableEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoNestedEnumOnSameEnumerable

  # Firing snippets lifted from no_nested_enum_on_same_enumerable_check_test.exs:
  #   defmodule Bad do
  #       def process(list) do
  #         Enum.map(list, fn x ->
  #           Enum.member?(list, x + 1)
  #         end)
  #       end
  #     end
  #   defmodule Good do
  #       def process(a, b) do
  #         Enum.map(a, fn x ->
  #           Enum.member?(b, x)
  #         end)
  #       end
  #     end
  #   defmodule Sibling do
  #       def f1([h | _t], xs), do: Enum.map(xs, fn x -> x + h end)
  #       def f1([], xs),       do: Enum.map(xs, fn x -> x * 2 end)
  #     end

  test "no_nested_enum_on_same_enumerable: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoNestedEnumOnSameEnumerable,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
