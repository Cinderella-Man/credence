defmodule Credence.Pattern.NoUnderscoreFunctionNameEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call) — compile before/after module, invoke a function.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoUnderscoreFunctionName

  # Firing snippets lifted from no_underscore_function_name_check_test.exs:
  #   defmodule Bad do
  #       def factorial(n), do: _factorial(n, 1)
  #       defp _factorial(0, acc), do: acc
  #       defp _factorial(n, acc), do: _factorial(n - 1, n * acc)
  #     end
  #   defmodule Bad do
  #       def _helper(x), do: x + 1
  #     end
  #   defmodule Bad do
  #       defp _fibonacci(count, acc, next) when count > 0 do
  #         _fibonacci(count - 1, next, acc + next)
  #       end
  #     end

  test "no_underscore_function_name: fix preserves the called function's behaviour over the battery" do
    assert_equivalent_module(
      """
      TODO: before module (lift a firing snippet from the check test)
      """,
      rule: NoUnderscoreFunctionName,
      call: {:todo_fun, 1},
      inputs: [[], [1, 2, 3], [:a, :b]]
    )
  end
end
