defmodule Credence.Pattern.NoTakeWhileLengthCheckEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoTakeWhileLengthCheck

  # Firing snippets lifted from no_take_while_length_check_check_test.exs:
  #   defmodule Bad do
  #       def palindrome?(graphemes, start, len) do
  #         half = div(len, 2)
  #         0..(half - 1)
  #         |> Enum.take_while(fn i ->
  #           Enum.at(graphemes, start + i) == Enum.at(graphemes, start + len - 1 - i)
  #         end)
  #         |> length() == half
  #       end
  #     end
  #   defmodule Bad do
  #       def count_matching(list) do
  #         list
  #         |> Enum.take_while(&(&1 > 0))
  #         |> Enum.count()
  #       end
  #     end
  #   defmodule Bad do
  #       def check(items) do
  #         Enum.take_while(items, &is_integer/1) |> length()
  #       end
  #     end

  test "no_take_while_length_check: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoTakeWhileLengthCheck,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
