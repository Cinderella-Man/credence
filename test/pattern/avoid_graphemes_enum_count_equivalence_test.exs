defmodule Credence.Pattern.AvoidGraphemesEnumCountEquivalenceTest do
  @moduledoc """
  Tier 1 (expression), Unicode. `string |> String.graphemes() |> Enum.count()` →
  `String.length(string)`. Both count graphemes, so they agree on every string
  including decomposed accents and flags.
  """
  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence
  alias Credence.EquivalenceBatteries, as: B
  alias Credence.Pattern.AvoidGraphemesEnumCount

  test "graphemes |> count → String.length preserves the count over Unicode" do
    assert_equivalent("string |> String.graphemes() |> Enum.count()",
      rule: AvoidGraphemesEnumCount,
      vars: [:string],
      inputs: B.unicode_strings()
    )
  end
end
