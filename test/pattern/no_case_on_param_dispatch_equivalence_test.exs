defmodule Credence.Pattern.NoCaseOnParamDispatchEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). A single-param total `case` in a function body splits into
  function heads: `def run(x), do: case x do 0 -> :zero; n -> {:ok, n} end` →
  `def run(0), do: :zero; def run(n), do: {:ok, n}`. The clause order and patterns
  are preserved, so dispatch is identical (CaseClauseError ⇄ FunctionClauseError is
  the only out-of-domain difference, and the case here is total).
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoCaseOnParamDispatch

  @before """
  defmodule Bad do
    def run(x) do
      case x do
        0 -> :zero
        n -> {:ok, n}
      end
    end
  end
  """

  test "case-on-param → function heads preserves dispatch" do
    assert_equivalent_module(@before,
      rule: NoCaseOnParamDispatch,
      call: {:run, 1},
      inputs: [0, 1, -5, :a, "s"]
    )
  end
end
