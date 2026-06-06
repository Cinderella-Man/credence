defmodule Credence.Pattern.NonGroupedClausesEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NonGroupedClauses

  # Firing snippets lifted from non_grouped_clauses_check_test.exs:
  #   defmodule M do
  #       def foo(1), do: 1
  #       def bar(x), do: x
  #       def foo(x), do: x + 1
  #     end
  #   defmodule M do
  #       defp helper(1), do: :one
  #       defp other(x), do: x
  #       defp helper(x), do: :other
  #     end
  #   defmodule M do
  #       def foo(1), do: 1
  #       def bar(1), do: 1
  #       def foo(x), do: x
  #       def bar(x), do: x
  #     end

  test "non_grouped_clauses: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NonGroupedClauses,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
