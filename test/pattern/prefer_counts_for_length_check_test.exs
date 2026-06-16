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

  # Safety boundary: `counts` and the `length` call live in unrelated scopes, so
  # the `counts` in scope at the call site is not the frequency map.
  test "does not flag a length call in a different scope" do
    assert clean?(PreferCountsForLength, """
           def a(string) do
             counts = string |> String.codepoints() |> Enum.frequencies()
             counts
           end

           def b(string) do
             length(String.codepoints(string))
           end
           """)
  end

  # Safety boundary: `counts` is reassigned before the `length` call, so
  # `Enum.sum(Map.values(counts))` would read a different map.
  test "does not flag when counts is reassigned before the length call" do
    assert clean?(PreferCountsForLength, """
           counts = string |> String.codepoints() |> Enum.frequencies()
           counts = %{}
           n = length(String.codepoints(string))
           n
           """)
  end

  # Safety boundary: `string` is rebound before the `length` call, so the two
  # traversals no longer see the same string.
  test "does not flag when string is rebound before the length call" do
    assert clean?(PreferCountsForLength, """
           counts = string |> String.codepoints() |> Enum.frequencies()
           string = other
           n = length(String.codepoints(string))
           n
           """)
  end
end
