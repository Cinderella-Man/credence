defmodule Credence.Pattern.PreferCountsForLengthFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferCountsForLength
  alias Credence.RuleHelpers

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

  test "does not rewrite a locally defined length/1 call" do
    input = """
    defmodule PreferCountsLocalLengthFixture do
      import Kernel, except: [length: 1]

      def length(_value), do: 41

      def count(string) do
        counts = string |> String.codepoints() |> Enum.frequencies()
        n = length(String.codepoints(string))
        {counts, n}
      end
    end
    """

    emitted = fix(PreferCountsForLength, input)
    confirm_fix(emitted, input)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(emitted)
  end

  test "does not rewrite calls through aliases that shadow standard modules" do
    input = """
    defmodule PreferCountsShadowedAliasesFixture do
      alias PreferCountsStringFixture, as: String
      alias PreferCountsEnumFixture, as: Enum
      alias PreferCountsMapFixture, as: Map

      def count(string) do
        counts = string |> String.codepoints() |> Enum.frequencies()
        n = length(String.codepoints(string))
        {counts, n}
      end
    end
    """

    emitted = fix(PreferCountsForLength, input)
    confirm_fix(emitted, input)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(emitted)
  end

  test "does not use the unreadable underscore as the counts value" do
    input = """
    defmodule PreferCountsUnderscoreFixture do
      def count(string) do
        _ = string |> String.codepoints() |> Enum.frequencies()
        n = length(String.codepoints(string))
        n
      end
    end
    """

    emitted = fix(PreferCountsForLength, input)
    confirm_fix(emitted, input)
    assert {:ok, _diagnostics} = RuleHelpers.compile_and_capture(emitted)
  end
end
