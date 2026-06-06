defmodule Credence.Pattern.NoManualFindEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoManualFind

  # Firing snippets lifted from no_manual_find_check_test.exs:
  #   defmodule Bad do
  #       defp find_positive([]), do: -1
  #       defp find_positive([h | _t]) when h > 0, do: h
  #       defp find_positive([_h | t]), do: find_positive(t)
  #     end
  #   defmodule Bad do
  #       defp find_first([], default), do: default
  #       defp find_first([h | _t], _default) when h > 0, do: h
  #       defp find_first([_h | t], default), do: find_first(t, default)
  #     end
  #   defmodule Bad do
  #       def find_positive([]), do: nil
  #       def find_positive([h | _]) when h > 0, do: h
  #       def find_positive([_ | t]), do: find_positive(t)
  #     end

  test "no_manual_find: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoManualFind,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
