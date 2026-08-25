defmodule Credence.Semantic.FixHallucinatedEnumRangeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixHallucinatedEnumRange

  defp compiles?(source), do: Credence.RuleHelpers.compiles?(source)

  @message "Enum.range/2 is undefined or private"

  defp fix(source, position) do
    FixHallucinatedEnumRange.fix(source, %{
      severity: :warning,
      message: @message,
      position: position
    })
  end

  test "replaces the flagged Enum.range with a range literal, parenthesizing the compound bound" do
    input = """
    defmodule HallucinatedEnumRange do
      def example(list) do
        Enum.reduce_while(
          Enum.range(0, length(list) - 1),
          :ok,
          fn i, _acc ->
            if i > 5, do: {:halt, :done}, else: {:cont, :ok}
          end
        )
      end
    end
    """

    expected = """
    defmodule HallucinatedEnumRange do
      def example(list) do
        Enum.reduce_while(
          0..(length(list) - 1),
          :ok,
          fn i, _acc ->
            if i > 5, do: {:halt, :done}, else: {:cont, :ok}
          end
        )
      end
    end
    """

    confirm_fix(fix(input, {4, 12}), expected)
  end

  test "fixes simple Enum.range(a, b) to a..b" do
    input = """
    defmodule CredenceEnumRangeSimple do
      def example do
        Enum.range(1, 10)
      end
    end
    """

    expected = """
    defmodule CredenceEnumRangeSimple do
      def example do
        1..10
      end
    end
    """

    confirm_fix(fix(input, {3, 10}), expected)
  end

  test "parenthesizes a compound first bound (.. binds tighter than -)" do
    input = """
    defmodule CredenceEnumRangeCompoundFirst do
      def example(n) do
        Enum.range(n - 3, n + 3)
      end
    end
    """

    expected = """
    defmodule CredenceEnumRangeCompoundFirst do
      def example(n) do
        (n - 3)..(n + 3)
      end
    end
    """

    confirm_fix(fix(input, {3, 10}), expected)
  end

  test "only the flagged call changes; an identical call on another line survives" do
    input = """
    defmodule CredenceEnumRangeTwoCalls do
      def a, do: Enum.range(1, 2)
      def b, do: Enum.range(3, 4)
    end
    """

    expected = """
    defmodule CredenceEnumRangeTwoCalls do
      def a, do: 1..2
      def b, do: Enum.range(3, 4)
    end
    """

    confirm_fix(fix(input, {2, 19}), expected)
  end

  test "fixes on a line-only position when the line has exactly one candidate" do
    input = """
    defmodule CredenceEnumRangeLineOnly do
      def example do
        Enum.range(1, 10)
      end
    end
    """

    expected = """
    defmodule CredenceEnumRangeLineOnly do
      def example do
        1..10
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "returns source unchanged when the column does not anchor on the call" do
    input = """
    defmodule CredenceEnumRangeBadCol do
      def example do
        Enum.range(1, 10)
      end
    end
    """

    confirm_fix(fix(input, {3, 1}), input)
  end

  test "returns source unchanged when the flagged line does not exist" do
    input = """
    defmodule CredenceEnumRangeBadLine do
      def example do
        Enum.range(1, 10)
      end
    end
    """

    confirm_fix(fix(input, {99, 10}), input)
  end

  test "returns source unchanged for the capture form (&Enum.range/2 admits no literal)" do
    input = """
    defmodule CredenceEnumRangeCaptureUnit do
      def a, do: &Enum.range/2
    end
    """

    confirm_fix(fix(input, {2, 20}), input)
  end

  test "returns source unchanged for the piped form" do
    input = """
    defmodule CredenceEnumRangePipeUnit do
      def a, do: 0 |> Enum.range(9)
    end
    """

    confirm_fix(fix(input, {2, 24}), input)
  end

  test "returns source unchanged for the Elixir.-prefixed spelling" do
    input = """
    defmodule CredenceEnumRangeElixirPrefixUnit do
      def a, do: Elixir.Enum.range(1, 5)
    end
    """

    confirm_fix(fix(input, {2, 26}), input)
  end

  test "returns source unchanged when no Enum.range present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, {2, 1}), input)
  end

  test "fixed flagship output is well-formed (parses)" do
    input = """
    defmodule CredenceEnumRangeParses do
      def example(list) do
        Enum.range(0, length(list) - 1)
      end
    end
    """

    assert valid_syntax?(fix(input, {3, 10}))
  end

  test "fixed flagship output compiles" do
    input = """
    defmodule CredenceEnumRangeCompiles do
      def example(list) do
        Enum.range(0, length(list) - 1)
      end
    end
    """

    assert compiles?(fix(input, {3, 10}))
  end

  test "compile checks contain top-level exits in fixtures" do
    refute compiles?("exit(:boom)")
  end

  test "end-to-end: the semantic phase fixes the flagship input and touches nothing else" do
    input = """
    defmodule CredenceEnumRangeE2E do
      def example(list) do
        Enum.reduce_while(
          Enum.range(0, length(list) - 1),
          :ok,
          fn i, _acc ->
            if i > 5, do: {:halt, :done}, else: {:cont, :ok}
          end
        )
      end
    end
    """

    expected = """
    defmodule CredenceEnumRangeE2E do
      def example(list) do
        Enum.reduce_while(
          0..(length(list) - 1),
          :ok,
          fn i, _acc ->
            if i > 5, do: {:halt, :done}, else: {:cont, :ok}
          end
        )
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: two flagged calls on one line are both fixed via their own columns" do
    input = """
    defmodule CredenceEnumRangeTwoOnLineE2E do
      def a, do: {Enum.range(1, 2), Enum.range(3, 4)}
    end
    """

    expected = """
    defmodule CredenceEnumRangeTwoOnLineE2E do
      def a, do: {1..2, 3..4}
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: an Enum.range spelling that resolves elsewhere via alias is left untouched" do
    input = """
    defmodule CredenceEnumRangeAliasShadowE2E do
      def a(list), do: Enum.range(0, length(list))

      def b do
        alias CredenceEnumRangeAliasShadowE2E.Ranges, as: Enum
        Enum.range(3, 4)
      end
    end
    """

    expected = """
    defmodule CredenceEnumRangeAliasShadowE2E do
      def a(list), do: 0..length(list)

      def b do
        alias CredenceEnumRangeAliasShadowE2E.Ranges, as: Enum
        Enum.range(3, 4)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the multi-line call form" do
    input = """
    defmodule CredenceEnumRangeMultilineE2E do
      def a(n) do
        Enum.range(
          0,
          n
        )
      end
    end
    """

    expected = """
    defmodule CredenceEnumRangeMultilineE2E do
      def a(n) do
        0..n
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the capture form is deliberately left unfixed" do
    input = """
    defmodule CredenceEnumRangeCaptureE2E do
      def a, do: &Enum.range/2
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end

  test "end-to-end: the piped form is deliberately left unfixed" do
    input = """
    defmodule CredenceEnumRangePipeE2E do
      def a, do: 0 |> Enum.range(9)
    end
    """

    confirm_fix(Credence.Semantic.fix(input), input)
  end
end
