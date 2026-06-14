defmodule Credence.Pattern.PreferFloatRoundEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), value-kind dimension.

  `:erlang.round(x * 100) / 100` → `Float.round(x, 2)`.

  Both return a float rounded to two decimal places. `Float.round/2` only
  accepts floats (raises on integers), so the input set is float-only.

  The inputs avoid "half" cases (values where `x * 100` is exactly `.5`),
  because `:erlang.round/1` uses banker's rounding (round half to even)
  while `Float.round/2` uses a different algorithm that can diverge on
  these edge cases.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferFloatRound

  # Float inputs that avoid half-cases (where x * 100 is exactly .5)
  @floats [0.0, 1.0, -1.0, 3.14, 2.72, -3.50, 1.01, 1.02, 1.12, 1.13, 1234.57]

  test ":erlang.round(x * 100) / 100 → Float.round(x, 2) preserves value+type over floats" do
    assert_equivalent(
      ":erlang.round(x * 100) / 100",
      rule: PreferFloatRound,
      vars: [:x],
      inputs: @floats
    )
  end
end
