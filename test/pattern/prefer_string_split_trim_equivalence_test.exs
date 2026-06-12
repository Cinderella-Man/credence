defmodule Credence.Pattern.PreferStringSplitTrimEquivalenceTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStringSplitTrim

  test "fix preserves behaviour" do
    assert_equivalent(
      """
      sentence
      |> String.split(~r/\s+/)
      |> Enum.filter(&(&1 != ""))
      """,
      rule: PreferStringSplitTrim,
      vars: [:sentence],
      inputs: [
        "",
        "hello",
        "  hello  world  ",
        "\thello\t",
        "hello\nworld",
        "  \t\n  ",
        "a b c d e f"
      ]
    )
  end
end
