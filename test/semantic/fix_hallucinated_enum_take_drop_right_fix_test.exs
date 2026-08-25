defmodule Credence.Semantic.FixHallucinatedEnumTakeDropRightFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.FixHallucinatedEnumTakeDropRight

  @take_message "Enum.take_right/2 is undefined or private"
  @drop_message "Enum.drop_right/2 is undefined or private"

  defp fix(source, message, position) do
    FixHallucinatedEnumTakeDropRight.fix(source, %{
      severity: :warning,
      message: message,
      position: position
    })
  end

  test "replaces the flagged Enum.take_right with Enum.take and a negated count" do
    input = """
    defmodule CredenceTakeRightSimple do
      def example(list, n) do
        Enum.take_right(list, n)
      end
    end
    """

    expected = """
    defmodule CredenceTakeRightSimple do
      def example(list, n) do
        Enum.take(list, -n)
      end
    end
    """

    confirm_fix(fix(input, @take_message, {3, 10}), expected)
  end

  test "replaces the flagged Enum.drop_right with Enum.drop and a negated literal" do
    input = """
    defmodule CredenceDropRightLiteral do
      def example(list) do
        Enum.drop_right(list, 2)
      end
    end
    """

    expected = """
    defmodule CredenceDropRightLiteral do
      def example(list) do
        Enum.drop(list, -2)
      end
    end
    """

    confirm_fix(fix(input, @drop_message, {3, 10}), expected)
  end

  test "folds a negative literal count into a positive one" do
    input = """
    defmodule CredenceTakeRightNegLiteral do
      def example(list) do
        Enum.take_right(list, -2)
      end
    end
    """

    expected = """
    defmodule CredenceTakeRightNegLiteral do
      def example(list) do
        Enum.take(list, 2)
      end
    end
    """

    confirm_fix(fix(input, @take_message, {3, 10}), expected)
  end

  test "cancels an already-negated variable count" do
    input = """
    defmodule CredenceDropRightNegVar do
      def example(list, n) do
        Enum.drop_right(list, -n)
      end
    end
    """

    expected = """
    defmodule CredenceDropRightNegVar do
      def example(list, n) do
        Enum.drop(list, n)
      end
    end
    """

    confirm_fix(fix(input, @drop_message, {3, 10}), expected)
  end

  test "parenthesizes a compound count (unary minus binds tighter than +)" do
    input = """
    defmodule CredenceTakeRightCompound do
      def example(list, n) do
        Enum.take_right(list, n + 1)
      end
    end
    """

    expected = """
    defmodule CredenceTakeRightCompound do
      def example(list, n) do
        Enum.take(list, -(n + 1))
      end
    end
    """

    confirm_fix(fix(input, @take_message, {3, 10}), expected)
  end

  test "only the flagged call changes; an identical call on another line survives" do
    input = """
    defmodule CredenceTakeRightTwoCalls do
      def a(l), do: Enum.take_right(l, 1)
      def b(l), do: Enum.take_right(l, 2)
    end
    """

    expected = """
    defmodule CredenceTakeRightTwoCalls do
      def a(l), do: Enum.take(l, -1)
      def b(l), do: Enum.take_right(l, 2)
    end
    """

    confirm_fix(fix(input, @take_message, {2, 22}), expected)
  end

  test "fixes on a line-only position when the line has exactly one candidate" do
    input = """
    defmodule CredenceTakeRightLineOnly do
      def example(list) do
        Enum.take_right(list, 3)
      end
    end
    """

    expected = """
    defmodule CredenceTakeRightLineOnly do
      def example(list) do
        Enum.take(list, -3)
      end
    end
    """

    confirm_fix(fix(input, @take_message, 3), expected)
  end

  test "returns source unchanged when the column does not anchor on the call" do
    input = """
    defmodule CredenceTakeRightBadCol do
      def example(list) do
        Enum.take_right(list, 3)
      end
    end
    """

    confirm_fix(fix(input, @take_message, {3, 1}), input)
  end

  test "returns source unchanged when the flagged line does not exist" do
    input = """
    defmodule CredenceTakeRightBadLine do
      def example(list) do
        Enum.take_right(list, 3)
      end
    end
    """

    confirm_fix(fix(input, @take_message, {99, 10}), input)
  end

  test "returns source unchanged when the message names the other function" do
    input = """
    defmodule CredenceTakeRightMismatch do
      def a(l), do: Enum.drop_right(l, 1)
    end
    """

    confirm_fix(fix(input, @take_message, {2, 22}), input)
  end

  test "rewrites the capture form as an anonymous function that negates the count" do
    input = """
    defmodule CredenceTakeRightCaptureUnit do
      def a, do: &Enum.take_right/2
    end
    """

    expected = """
    defmodule CredenceTakeRightCaptureUnit do
      def a, do: fn enumerable, count -> Enum.take(enumerable, -count) end
    end
    """

    confirm_fix(fix(input, @take_message, {2, 20}), expected)
  end

  test "rewrites the piped form" do
    input = """
    defmodule CredenceTakeRightPipeUnit do
      def a(l), do: l |> Enum.take_right(2)
    end
    """

    expected = """
    defmodule CredenceTakeRightPipeUnit do
      def a(l), do: Enum.take(l, -2)
    end
    """

    confirm_fix(fix(input, @take_message, {2, 27}), expected)
  end

  test "rewrites the Elixir.-prefixed spelling" do
    input = """
    defmodule CredenceTakeRightElixirPrefixUnit do
      def a(l), do: Elixir.Enum.take_right(l, 5)
    end
    """

    expected = """
    defmodule CredenceTakeRightElixirPrefixUnit do
      def a(l), do: Elixir.Enum.take(l, -5)
    end
    """

    confirm_fix(fix(input, @take_message, {2, 29}), expected)
  end

  test "returns source unchanged when no hallucinated call is present" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @take_message, {2, 1}), input)
  end

  test "fixed flagship output is well-formed (parses)" do
    input = """
    defmodule CredenceTakeRightParses do
      def example(list, n) do
        Enum.take_right(list, n)
      end
    end
    """

    assert valid_syntax?(fix(input, @take_message, {3, 10}))
  end

  test "fixed flagship output compiles" do
    input = """
    defmodule CredenceTakeRightCompiles do
      def example(list, n) do
        Enum.take_right(list, n)
      end
    end
    """

    assert compiles?(fix(input, @take_message, {3, 10}))
  end

  test "end-to-end: the semantic phase fixes both functions and touches nothing else" do
    input = """
    defmodule CredenceTakeDropRightE2E do
      def take(list), do: Enum.take_right(list, 2)
      def drop(list), do: Enum.drop_right(list, 3)
    end
    """

    expected = """
    defmodule CredenceTakeDropRightE2E do
      def take(list), do: Enum.take(list, -2)
      def drop(list), do: Enum.drop(list, -3)
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: two flagged calls on one line are both fixed via their own columns" do
    input = """
    defmodule CredenceTakeRightTwoOnLineE2E do
      def a(l), do: {Enum.take_right(l, 1), Enum.take_right(l, 2)}
    end
    """

    expected = """
    defmodule CredenceTakeRightTwoOnLineE2E do
      def a(l), do: {Enum.take(l, -1), Enum.take(l, -2)}
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: a spelling that resolves elsewhere via alias is left untouched" do
    input = """
    defmodule CredenceTakeRightAliasShadowE2E do
      def a(list), do: Enum.take_right(list, 1)

      def b do
        alias CredenceTakeRightAliasShadowE2E.Lists, as: Enum
        Enum.take_right([1, 2, 3], 2)
      end
    end
    """

    expected = """
    defmodule CredenceTakeRightAliasShadowE2E do
      def a(list), do: Enum.take(list, -1)

      def b do
        alias CredenceTakeRightAliasShadowE2E.Lists, as: Enum
        Enum.take_right([1, 2, 3], 2)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the multi-line call form" do
    input = """
    defmodule CredenceTakeRightMultilineE2E do
      def a(list, n) do
        Enum.take_right(
          list,
          n
        )
      end
    end
    """

    expected = """
    defmodule CredenceTakeRightMultilineE2E do
      def a(list, n) do
        Enum.take(list, -n)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the capture form is fixed" do
    input = """
    defmodule CredenceTakeRightCaptureE2E do
      def a, do: &Enum.take_right/2
    end
    """

    expected = """
    defmodule CredenceTakeRightCaptureE2E do
      def a, do: fn enumerable, count -> Enum.take(enumerable, -count) end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the piped form is fixed" do
    input = """
    defmodule CredenceTakeRightPipeE2E do
      def a(l), do: l |> Enum.take_right(2)
    end
    """

    expected = """
    defmodule CredenceTakeRightPipeE2E do
      def a(l), do: Enum.take(l, -2)
    end
    """

    fixed = Credence.Semantic.fix(input)

    confirm_fix(fixed, expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(fixed)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(expected)
  end
end
