defmodule Credence.Pattern.NoUnnecessaryCatchAllRaiseEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoUnnecessaryCatchAllRaise

  # Firing snippets lifted from no_unnecessary_catch_all_raise_check_test.exs:
  #   defmodule Bad do
  #       def missing_number([]), do: 0
  #       def missing_number(nums) when is_list(nums), do: length(nums)
  #       def missing_number(_), do: raise(ArgumentError, "expected a list")
  #     end
  #   defmodule Bad do
  #       def foo(x) when is_integer(x), do: x + 1
  #       def foo(_), do: raise("invalid argument")
  #     end
  #   defmodule Bad do
  #       defp process([h | t]), do: {h, t}
  #       defp process(_), do: raise(ArgumentError, "must be a list")
  #     end

  test "no_unnecessary_catch_all_raise: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoUnnecessaryCatchAllRaise,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
