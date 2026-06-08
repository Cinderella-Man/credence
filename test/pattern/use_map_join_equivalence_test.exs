defmodule Credence.Pattern.UseMapJoinEquivalenceTest do
  @moduledoc """
  PROBE (eval-order / double-eval).

  `Enum.map(list, f) |> Enum.join(sep)` → `Enum.map_join(list, sep, f)`.

  Value parity alone can't prove the mapper `f` runs over the same elements in
  the same order and the same number of times. We put the mapper in the `effect`
  hole (a recording fn) and assert the call-trace (order + count) is identical
  between original and fixed.
  """
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.UseMapJoin

  test "map |> join → map_join preserves mapper call order and count" do
    assert_effect_trace_equivalent(
      """
      Enum.map(list, fn x -> effect.(x) end) |> Enum.join(sep)
      """,
      rule: UseMapJoin,
      vars: [:list, :sep],
      inputs: [
        {[], "-"},
        {[1], ","},
        {[1, 2, 3], "-"},
        {[:a, :b, :c, :d], ", "}
      ]
    )
  end
end
