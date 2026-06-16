defmodule Credence.Pattern.PreferPipeMapsetIntersectionEquivalenceTest do
  @moduledoc """
  Tier 2 (module-call). The fix rewrites MapSet.new assignments + nested
  intersection into a pipeline. Both before/after produce the same intersection
  result for every input.
  """
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPipeMapsetIntersection

  test "fix preserves behaviour for three-variable case" do
    assert_equivalent_module(
      """
      defmodule BeforePipeMapset do
        def get_common(a, b, c) do
          set_a = MapSet.new(a)
          set_b = MapSet.new(b)
          set_c = MapSet.new(c)

          MapSet.intersection(set_a, MapSet.intersection(set_b, set_c))
          |> MapSet.to_list()
        end
      end
      """,
      rule: PreferPipeMapsetIntersection,
      call: {:get_common, 3},
      inputs: [
        {[1, 2, 3], [2, 3, 4], [3, 4, 5]},
        {[1, 2], [2, 3], [3, 4]},
        {[], [1, 2], [2, 3]},
        {[1, 2, 3, 4], [2, 3, 4, 5], [3, 4, 5, 6]},
        {[:a, :b, :c], [:b, :c, :d], [:c, :d, :e]}
      ]
    )
  end

  test "fix preserves behaviour for two-variable case" do
    assert_equivalent_module(
      """
      defmodule BeforePipeMapset2 do
        def get_common(a, b) do
          set_a = MapSet.new(a)
          set_b = MapSet.new(b)

          MapSet.intersection(set_a, set_b) |> MapSet.to_list()
        end
      end
      """,
      rule: PreferPipeMapsetIntersection,
      call: {:get_common, 2},
      inputs: [
        {[1, 2, 3], [2, 3, 4]},
        {[1, 2], [3, 4]},
        {[], [1, 2, 3]},
        {[:a, :b], [:b, :c]},
        {[1, 1, 2, 2], [2, 2, 3, 3]}
      ]
    )
  end
end
