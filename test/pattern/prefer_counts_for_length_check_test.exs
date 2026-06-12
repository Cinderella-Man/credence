defmodule Credence.Pattern.PreferCountsForLengthCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferCountsForLength

  test "flags the anti-pattern" do
    assert flagged?(PreferCountsForLength, """
    counts = string |> String.codepoints() |> Enum.frequencies()
    n = length(String.codepoints(string))
    n
    """)
  end

  test "leaves good code alone" do
    assert clean?(PreferCountsForLength, """
    n = length(String.codepoints(string))
    n
    """)
  end
end
