defmodule Credence.Pattern.NoReduceForGroupByEquivalenceTest do
  @moduledoc """
  Tier 1 + PROBE — eval-order/double-eval over a transform hole.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.NoReduceForGroupBy

  # Firing snippets lifted from no_reduce_for_group_by_check_test.exs:
  #   defmodule Bad do
  #       def group(list) do
  #         Enum.reduce(list, %{}, fn x, acc ->
  #           Map.update(acc, String.first(x), [x], &[x | &1])
  #         end)
  #         |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  #       end
  #     end
  #   defmodule Bad do
  #       def group(list) do
  #         Enum.reduce(list, %{}, fn x, acc ->
  #           key = String.first(x)
  #           Map.update(acc, key, [x], &[x | &1])
  #         end)
  #         |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  #       end
  #     end
  #   defmodule Bad do
  #       def group(list) do
  #         list
  #         |> Enum.reduce(%{}, fn x, acc ->
  #           Map.update(acc, String.first(x), [x], &[x | &1])
  #         end)
  #         |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  #       end
  #     end

  test "no_reduce_for_group_by: fix preserves transform call order/count over the battery" do
    assert_effect_trace_equivalent(
      "TODO: firing expression with the transform hole written as `effect.(x)`",
      rule: NoReduceForGroupBy,
      vars: [:list],
      inputs: [{[1, 2, 3], "-"}]
    )
  end
end
