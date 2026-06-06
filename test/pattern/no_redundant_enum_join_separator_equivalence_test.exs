defmodule Credence.Pattern.NoRedundantEnumJoinSeparatorEquivalenceTest do
  @moduledoc """
  Tier 1 (expression) — wrap before/after in `fn <vars> -> expr end`.

  AUTO-GENERATED SKELETON (docs/07 Phase 2). Fill the snippet + battery, confirm
  the tier, then delete the `@moduletag :equivalence_todo` line.
  """
  use ExUnit.Case, async: true
  @moduletag :equivalence_todo

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.NoRedundantEnumJoinSeparator

  # Firing snippets lifted from no_redundant_enum_join_separator_check_test.exs:
  #   Enum.join(list, "")
  #   defmodule M do
  #       def f(a, b) do
  #         x = Enum.join(a, "")
  #         y = b |> Enum.join("")
  #         z = Enum.map_join(a, "", &to_string/1)
  #         w = b |> Enum.map_join("", &to_string/1)
  #         {x, y, z, w}
  #       end
  #     end
  #   list |> Enum.map_join("", &to_string/1)

  test "no_redundant_enum_join_separator: fix preserves behaviour over the battery" do
    assert_equivalent(
      "TODO: firing expression (bind its free vars below)",
      rule: NoRedundantEnumJoinSeparator,
      vars: [:todo],
      inputs: B.term_lists()
    )
  end
end
