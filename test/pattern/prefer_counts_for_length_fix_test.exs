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

  test "leaves good code untouched" do
    input = """
    n = length(String.codepoints(string))
    n
    """

    confirm_fix(fix(PreferCountsForLength, input), input)
  end

  test "does not rewrite a length call in a different scope" do
    input = """
    def a(string) do
      counts = string |> String.codepoints() |> Enum.frequencies()
      counts
    end

    def b(string) do
      length(String.codepoints(string))
    end
    """

    confirm_fix(fix(PreferCountsForLength, input), input)
  end

  test "does not rewrite when counts is reassigned before the length call" do
    input = """
    counts = string |> String.codepoints() |> Enum.frequencies()
    counts = %{}
    n = length(String.codepoints(string))
    n
    """

    confirm_fix(fix(PreferCountsForLength, input), input)
  end

  test "does not rewrite when string is rebound before the length call" do
    input = """
    counts = string |> String.codepoints() |> Enum.frequencies()
    string = other
    n = length(String.codepoints(string))
    n
    """

    confirm_fix(fix(PreferCountsForLength, input), input)
  end
end
