defmodule Credence.Pattern.PreferMapSizeEquivalenceTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapSize

  test "fix preserves behaviour" do
    assert_equivalent(
      """
      Map.keys(m) |> Enum.count()
      """,
      rule: PreferMapSize,
      vars: [:m],
      inputs: [
        %{},
        %{a: 1},
        %{a: 1, b: 2, c: 3},
        %{x: 10, y: 20},
        %{1 => :a, 2 => :b, "three" => :c}
      ]
    )
  end
end
