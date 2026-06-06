defmodule Credence.Pattern.NoManualEnumUniqEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoManualEnumUniq

  # Firing snippets lifted from no_manual_enum_uniq_check_test.exs:
  #   defmodule Example do
  #       def run(list) do
  #         Enum.reduce(list, {MapSet.new(), []}, fn item, {seen, acc} ->
  #           if MapSet.member?(seen, item) do
  #             {seen, acc}
  #           else
  #             {MapSet.put(seen, item), [item | acc]}
  #           end
  #         end)
  #       end
  #     end
  #   defmodule Example do
  #       def run(list) do
  #         Enum.reduce(list, {[], MapSet.new()}, fn x, {results, tracked} ->
  #           unless MapSet.member?(tracked, x) do
  #             {[x | results], MapSet.put(tracked, x)}
  #           else
  #             {results, tracked}
  #           end
  #         end)
  #       end
  #     end
  #   defmodule Example do
  #       def run(list) do
  #         list
  #         |> Enum.reduce({MapSet.new(), []}, fn item, {seen, acc} ->
  #           if MapSet.member?(seen, item) do
  #             {seen, acc}
  #           else
  #             {MapSet.put(seen, item), [item | acc]}
  #           end
  #         end)
  #       end
  #     end

  test "no_manual_enum_uniq: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoManualEnumUniq,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
