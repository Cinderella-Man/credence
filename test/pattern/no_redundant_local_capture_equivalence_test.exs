defmodule Credence.Pattern.NoRedundantLocalCaptureEquivalenceTest do
  @moduledoc """
  Tier 2 (module). A redundant capture `factorial = &factorial/1` with
  `factorial.(n)` is replaced by direct `factorial(n)` calls. The fix
  preserves the return value and type for all inputs.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantLocalCapture

  test "direct call preserves behaviour" do
    assert_equivalent_module(
      """
      defmodule Example do
        def compute(n) do
          factorial = &factorial/1
          div(factorial.(2 * n), div(factorial.(n) * factorial.(n + 1), 1))
        end

        defp factorial(0), do: 1
        defp factorial(n) when n > 0 do
          Enum.product(1..n)
        end
      end
      """,
      rule: NoRedundantLocalCapture,
      call: {:compute, 1},
      inputs: [0, 1, 2, 3, 5, 10]
    )
  end
end
