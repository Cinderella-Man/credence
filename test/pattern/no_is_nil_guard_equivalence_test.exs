defmodule Credence.Pattern.NoIsNilGuardEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoIsNilGuard

  # Firing snippets lifted from no_is_nil_guard_check_test.exs:
  #   def foo(x) when is_nil(x), do: :bar
  #   defmodule E do
  #       def foo(x) when is_nil(x), do: :bar
  #       def bar(y) when is_nil(y), do: :baz
  #     end
  #   def foo(x, y) when is_nil(x) and is_binary(y), do: :ok

  test "no_is_nil_guard: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoIsNilGuard,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
