defmodule Credence.Pattern.PreferChunkOverIndexedReduceEquivalenceTest do
  use Credence.RuleCase, async: true

  import Credence.BehaviourEquivalence
  alias Credence.Pattern.PreferChunkOverIndexedReduce

  test "fix preserves behaviour" do
    assert_equivalent(
      """
      list
      |> Stream.with_index()
      |> Enum.reduce(0, fn {value, index}, acc ->
        cond do
          index == 0 ->
            if value > Enum.at(list, 1) do
              acc + 1
            else
              acc
            end

          index == length(list) - 1 ->
            if value > Enum.at(list, index - 1) do
              acc + 1
            else
              acc
            end

          true ->
            left = Enum.at(list, index - 1)
            right = Enum.at(list, index + 1)

            if value > left and value > right do
              acc + 1
            else
              acc
            end
        end
      end)
      """,
      rule: PreferChunkOverIndexedReduce,
      vars: [:list],
      inputs: [
        [1, 2, 3, 2, 1],
        [3, 1, 4, 1, 5, 9],
        [1, 3, 2, 4, 3, 5],
        [5, 4, 3, 2, 1],
        [1, 2, 3, 4, 5]
      ]
    )
  end
end
