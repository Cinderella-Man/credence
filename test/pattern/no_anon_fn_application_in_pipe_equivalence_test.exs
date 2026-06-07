defmodule Credence.Pattern.NoAnonFnApplicationInPipeEquivalenceTest do
  @moduledoc """
  Tier 1 (expression). `value |> (fn x -> ... end).()` → `value |> then(fn x -> ... end)`.
  Both apply the anonymous function to the piped value exactly once, so the result
  is identical. Input set covers several piped values.

  Regression note: the fix's patch range used to start at the `fn` keyword,
  stranding the parenthesized fn's leading `(` and producing the uncompilable
  `value |> (then(fn ... end)`. The range is now extended one column left to
  swallow that `(`; verified valid for single, chained, and multi-line forms.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoAnonFnApplicationInPipe

  test "value |> (fn x -> ... end).() → then(fn) preserves the result" do
    assert_equivalent("list |> Enum.sort() |> (fn s -> [1 | s] end).()",
      rule: NoAnonFnApplicationInPipe,
      vars: [:list],
      inputs: [[], [3, 1, 2], [1], [2, 2, 1], [-1, -5, 0]]
    )
  end

  test "chained applications → chained then/2 preserve the result" do
    assert_equivalent("x |> (fn a -> a + 1 end).() |> (fn b -> b * 2 end).()",
      rule: NoAnonFnApplicationInPipe,
      vars: [:x],
      inputs: [0, 1, -3, 10, 100]
    )
  end
end
