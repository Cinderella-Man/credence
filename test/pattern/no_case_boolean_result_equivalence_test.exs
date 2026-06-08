defmodule Credence.Pattern.NoCaseBooleanResultEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). `case x do :ok -> true; _ -> false end` collapses to the
  boolean test itself. The catch-all `_ -> false` makes it total, so the rewrite
  matches for every input.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoCaseBooleanResult

  @before """
  defmodule Bad do
    def f(result) do
      case result do
        :ok -> true
        _ -> false
      end
    end
  end
  """

  test "case → true/false collapses to the boolean test, preserving the result" do
    assert_equivalent_module(@before,
      rule: NoCaseBooleanResult,
      call: {:f, 1},
      inputs: [:ok, :error, 1, nil, "ok"]
    )
  end
end
