defmodule Credence.Pattern.NoStringConcatInLoopEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoStringConcatInLoop

  # Firing snippets lifted from no_string_concat_in_loop_check_test.exs:
  #   defmodule Example do
  #       def build(list) do
  #         Enum.reduce(list, "", fn char, acc -> acc <> char end)
  #       end
  #     end
  #   defmodule Example do
  #       def build(list) do
  #         Enum.reduce(list, "", fn char, acc -> acc <> to_string(char) end)
  #       end
  #     end
  #   defmodule Example do
  #       def build(list) do
  #         list |> Enum.reduce("", fn char, acc -> acc <> char end)
  #       end
  #     end

  test "no_string_concat_in_loop: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoStringConcatInLoop,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
