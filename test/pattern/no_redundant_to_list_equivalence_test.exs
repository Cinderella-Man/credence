defmodule Credence.Pattern.NoRedundantToListEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoRedundantToList

  # Firing snippets lifted from no_redundant_to_list_check_test.exs:
  #   defmodule Example do
  #       def run(items) do
  #         MapSet.new(items)
  #       end
  #     end
  #   defmodule Example do
  #       def run(items) do
  #         Enum.to_list(items)
  #       end
  #     end
  #   defmodule Example do
  #       def run(items) do
  #         Enum.to_list(items) |> IO.inspect()
  #       end
  #     end

  test "no_redundant_to_list: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoRedundantToList,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
