defmodule Credence.Pattern.PreferCountsForLengthFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferCountsForLength

  test "rewrites the anti-pattern" do
    input = """
    counts = string |> String.codepoints() |> Enum.frequencies()
    n = length(String.codepoints(string))
    n
    """

    expected = """
    counts = string |> String.codepoints() |> Enum.frequencies()
    n = Enum.sum(Map.values(counts))
    n
    """

    confirm_fix(fix(PreferCountsForLength, input), expected)
  end
end
