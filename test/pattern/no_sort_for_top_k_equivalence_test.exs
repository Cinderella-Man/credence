defmodule Credence.Pattern.NoSortForTopKEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoSortForTopK

  # Firing snippets lifted from no_sort_for_top_k_check_test.exs:
  #   defmodule Bad do
  #       def f(list), do: Enum.sort(list) |> Enum.take(1)
  #     end
  #   defmodule Bad do
  #       def f(list), do: Enum.sort(list) |> hd()
  #     end
  #   defmodule Bad do
  #       def f(list), do: Enum.sort(list) |> Enum.at(0)
  #     end

  test "no_sort_for_top_k: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoSortForTopK,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
