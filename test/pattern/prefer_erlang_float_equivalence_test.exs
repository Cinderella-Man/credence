defmodule Credence.Pattern.PreferErlangFloatEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), value-kind dimension.

  Float-coercion tricks → `:erlang.float/1`, for bare-variable and compound
  operands alike: `n * 1.0` → `:erlang.float(n)`,
  `Enum.sum(list) * 1.0` → `:erlang.float(Enum.sum(list))`.

  This is the merge of the old `prefer_erlang_float` (bare vars) and
  `no_identity_float_coercion` (compound, which used to *remove* the coercion).
  Removal was a value-kind bug — `6.0` became `6`; wrapping preserves the float
  exactly. The input set is numeric (int / float / negative / zero / big), where
  the value-kind risk lives. A non-number operand raises in both forms (only the
  exception module differs — intentionally out of scope; see the rule moduledoc).
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferErlangFloat

  @numbers [0, 1, -1, 7, -7, 42, 1000, 1_000_000, 1.0, 2.5, -3.5, 0.0]

  test "bare var: n * 1.0 → :erlang.float(n) preserves value+type over numbers" do
    assert_equivalent("n * 1.0",
      rule: PreferErlangFloat,
      vars: [:n],
      inputs: @numbers
    )
  end

  test "compound operand: abs(n) * 1.0 → :erlang.float(abs(n)) preserves value+type" do
    assert_equivalent("abs(n) * 1.0",
      rule: PreferErlangFloat,
      vars: [:n],
      inputs: @numbers
    )
  end

  test "division operand: (n / 2) + 0.0 → :erlang.float(n / 2) preserves value+type" do
    assert_equivalent("(n / 2) + 0.0",
      rule: PreferErlangFloat,
      vars: [:n],
      inputs: @numbers
    )
  end
end
