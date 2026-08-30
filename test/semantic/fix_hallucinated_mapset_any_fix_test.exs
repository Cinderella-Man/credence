defmodule Credence.Semantic.FixHallucinatedMapsetAnyFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.FixHallucinatedMapsetAny

  @message "MapSet.any?/2 is undefined or private"

  defp fix(source, position) do
    FixHallucinatedMapsetAny.fix(source, %{
      severity: :warning,
      message: @message,
      position: position
    })
  end

  test "renames the flagged MapSet.any? to Enum.any?, leaving MapSet.member? alone" do
    input = """
    defmodule CredenceMapsetAnyFlagship do
      def has_active?(mapset, tombstones) do
        MapSet.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    expected = """
    defmodule CredenceMapsetAnyFlagship do
      def has_active?(mapset, tombstones) do
        Enum.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    confirm_fix(fix(input, {3, 12}), expected)
  end

  test "fixes the piped form (the rename needs no structural rewrite)" do
    input = """
    defmodule CredenceMapsetAnyPiped do
      def run(set, pred), do: set |> MapSet.any?(pred)
    end
    """

    expected = """
    defmodule CredenceMapsetAnyPiped do
      def run(set, pred), do: set |> Enum.any?(pred)
    end
    """

    confirm_fix(fix(input, {2, 41}), expected)
  end

  test "fixes the capture form (&Enum.any?/2 exists)" do
    input = """
    defmodule CredenceMapsetAnyCapture do
      def checker, do: &MapSet.any?/2
    end
    """

    expected = """
    defmodule CredenceMapsetAnyCapture do
      def checker, do: &Enum.any?/2
    end
    """

    confirm_fix(fix(input, {2, 28}), expected)
  end

  test "a multi-line call keeps its arguments byte-for-byte" do
    input = """
    defmodule CredenceMapsetAnyMultiline do
      def run(set) do
        MapSet.any?(
          set,
          fn x ->
            x > 10
          end
        )
      end
    end
    """

    expected = """
    defmodule CredenceMapsetAnyMultiline do
      def run(set) do
        Enum.any?(
          set,
          fn x ->
            x > 10
          end
        )
      end
    end
    """

    confirm_fix(fix(input, {3, 12}), expected)
  end

  test "unusual spacing inside the call survives byte-for-byte" do
    input = """
    defmodule CredenceMapsetAnySpacing do
      def a(s, p), do: MapSet.any?( s,   p )
    end
    """

    expected = """
    defmodule CredenceMapsetAnySpacing do
      def a(s, p), do: Enum.any?( s,   p )
    end
    """

    confirm_fix(fix(input, {2, 27}), expected)
  end

  test "only the flagged call changes; an identical call on another line survives" do
    input = """
    defmodule CredenceMapsetAnyTwoCalls do
      def a(s, p), do: MapSet.any?(s, p)
      def b(s, p), do: MapSet.any?(s, p)
    end
    """

    expected = """
    defmodule CredenceMapsetAnyTwoCalls do
      def a(s, p), do: Enum.any?(s, p)
      def b(s, p), do: MapSet.any?(s, p)
    end
    """

    confirm_fix(fix(input, {2, 27}), expected)
  end

  test "fixes on a line-only position when the line has exactly one candidate" do
    input = """
    defmodule CredenceMapsetAnyLineOnly do
      def has_active?(mapset, tombstones) do
        MapSet.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    expected = """
    defmodule CredenceMapsetAnyLineOnly do
      def has_active?(mapset, tombstones) do
        Enum.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "returns source unchanged when the column does not anchor on the call" do
    input = """
    defmodule CredenceMapsetAnyBadCol do
      def run(set, pred) do
        MapSet.any?(set, pred)
      end
    end
    """

    confirm_fix(fix(input, {3, 1}), input)
  end

  test "returns source unchanged when the flagged line does not exist" do
    input = """
    defmodule CredenceMapsetAnyBadLine do
      def run(set, pred) do
        MapSet.any?(set, pred)
      end
    end
    """

    confirm_fix(fix(input, {99, 12}), input)
  end

  test "returns source unchanged for the Elixir.-prefixed spelling" do
    input = """
    defmodule CredenceMapsetAnyElixirPrefix do
      def a(s, p), do: Elixir.MapSet.any?(s, p)
    end
    """

    confirm_fix(fix(input, {2, 34}), input)
  end

  test "returns source unchanged when no MapSet.any? present" do
    input = """
    defmodule CleanExample do
      def check(set), do: MapSet.member?(set, :foo)
    end
    """

    confirm_fix(fix(input, {2, 1}), input)
  end

  test "fixed flagship output is well-formed (parses)" do
    input = """
    defmodule CredenceMapsetAnyParses do
      def has_active?(mapset, tombstones) do
        MapSet.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    assert valid_syntax?(fix(input, {3, 12}))
  end

  test "fixed flagship output compiles" do
    input = """
    defmodule CredenceMapsetAnyCompiles do
      def has_active?(mapset, tombstones) do
        MapSet.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    assert compiles?(fix(input, {3, 12}))
  end

  test "end-to-end: the semantic phase fixes the flagship input and touches nothing else" do
    input = """
    defmodule CredenceMapsetAnyE2E do
      def has_active?(mapset, tombstones) do
        MapSet.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    expected = """
    defmodule CredenceMapsetAnyE2E do
      def has_active?(mapset, tombstones) do
        Enum.any?(mapset, fn tag -> not MapSet.member?(tombstones, tag) end)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: two flagged calls on one line are both fixed via their own columns" do
    input = """
    defmodule CredenceMapsetAnyTwoOnLineE2E do
      def a(s, p, q), do: {MapSet.any?(s, p), MapSet.any?(s, q)}
    end
    """

    expected = """
    defmodule CredenceMapsetAnyTwoOnLineE2E do
      def a(s, p, q), do: {Enum.any?(s, p), Enum.any?(s, q)}
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: a MapSet.any? spelling that resolves elsewhere via alias is left untouched" do
    input = """
    defmodule CredenceMapsetAnyAliasShadowE2E do
      def a(set), do: MapSet.any?(set, fn x -> x > 0 end)

      def b(set, pred) do
        alias CredenceMapsetAnyAliasShadowE2E.CustomSet, as: MapSet
        MapSet.any?(set, pred)
      end
    end
    """

    expected = """
    defmodule CredenceMapsetAnyAliasShadowE2E do
      def a(set), do: Enum.any?(set, fn x -> x > 0 end)

      def b(set, pred) do
        alias CredenceMapsetAnyAliasShadowE2E.CustomSet, as: MapSet
        MapSet.any?(set, pred)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the piped form is fixed" do
    input = """
    defmodule CredenceMapsetAnyPipedE2E do
      def run(set, pred), do: set |> MapSet.any?(pred)
    end
    """

    expected = """
    defmodule CredenceMapsetAnyPipedE2E do
      def run(set, pred), do: set |> Enum.any?(pred)
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the capture form is fixed" do
    input = """
    defmodule CredenceMapsetAnyCaptureE2E do
      def checker, do: &MapSet.any?/2
    end
    """

    expected = """
    defmodule CredenceMapsetAnyCaptureE2E do
      def checker, do: &Enum.any?/2
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end
end
