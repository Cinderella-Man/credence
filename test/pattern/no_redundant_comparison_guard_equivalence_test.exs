defmodule Credence.Pattern.NoRedundantComparisonGuardEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). When earlier clauses already constrain the value, a trailing
  comparison guard is redundant: `sqrt(n) when is_number(n) and n < 0 -> raise; sqrt(0);
  sqrt(n) when is_number(n) and n >= 0` → the final `n >= 0` is dropped (any number
  reaching it is already ≥ 0). The retained `is_number(n)` keeps non-numbers out, so
  dispatch — including the FunctionClauseError on a non-number — is preserved.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoRedundantComparisonGuard

  @before """
  defmodule Bad do
    def sqrt(n) when is_number(n) and n < 0, do: raise(ArgumentError)
    def sqrt(0), do: 0.0
    def sqrt(n) when is_number(n) and n >= 0, do: :ok
  end
  """

  test "dropping the redundant comparison guard preserves dispatch incl. non-number" do
    assert_equivalent_module(@before,
      rule: NoRedundantComparisonGuard,
      call: {:sqrt, 1},
      inputs: [0, 4, 100, :a, "s"]
    )
  end
end
