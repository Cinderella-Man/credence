defmodule Credence.Semantic.FixHallucinatedStreamDataFlatMapFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.FixHallucinatedStreamDataFlatMap

  @message "StreamData.flat_map/2 is undefined or private"

  defp fix(source, position) do
    FixHallucinatedStreamDataFlatMap.fix(source, %{
      severity: :warning,
      message: @message,
      position: position
    })
  end

  test "renames the flagged StreamData.flat_map to StreamData.bind" do
    input = """
    defmodule CredenceStreamDataFlatMapFlagship do
      def sized_lists do
        StreamData.flat_map(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapFlagship do
      def sized_lists do
        StreamData.bind(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    confirm_fix(fix(input, {3, 16}), expected)
  end

  test "fixes the piped form (the rename needs no structural rewrite)" do
    input = """
    defmodule CredenceStreamDataFlatMapPiped do
      def gen(inner, fun) do
        inner |> StreamData.flat_map(fun)
      end
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapPiped do
      def gen(inner, fun) do
        inner |> StreamData.bind(fun)
      end
    end
    """

    confirm_fix(fix(input, {3, 25}), expected)
  end

  test "fixes the capture form (&StreamData.bind/2 exists)" do
    input = """
    defmodule CredenceStreamDataFlatMapCapture do
      def combinator do
        &StreamData.flat_map/2
      end
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapCapture do
      def combinator do
        &StreamData.bind/2
      end
    end
    """

    confirm_fix(fix(input, {3, 17}), expected)
  end

  test "fixes a call through a short alias using the emitted diagnostic" do
    input = """
    defmodule CredenceStreamDataFlatMapShortAlias do
      alias StreamData, as: SD
      def gen(g, f), do: SD.flat_map(g, f)
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapShortAlias do
      alias StreamData, as: SD
      def gen(g, f), do: SD.bind(g, f)
    end
    """

    assert {:ok, diagnostics} = Credence.RuleHelpers.compile_and_capture(input)

    diagnostic = Enum.find(diagnostics, &(&1.message == @message))

    assert diagnostic
    confirm_fix(FixHallucinatedStreamDataFlatMap.fix(input, diagnostic), expected)
    assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "a multi-line call keeps its arguments byte-for-byte" do
    input = """
    defmodule CredenceStreamDataFlatMapMultiline do
      def gen(base, fun) do
        StreamData.flat_map(
          base,
          fun
        )
      end
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapMultiline do
      def gen(base, fun) do
        StreamData.bind(
          base,
          fun
        )
      end
    end
    """

    confirm_fix(fix(input, {3, 16}), expected)
  end

  test "unusual spacing inside the call survives byte-for-byte" do
    input = """
    defmodule CredenceStreamDataFlatMapSpacing do
      def a(g, f), do: StreamData.flat_map( g,   f )
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapSpacing do
      def a(g, f), do: StreamData.bind( g,   f )
    end
    """

    confirm_fix(fix(input, {2, 31}), expected)
  end

  test "only the flagged call changes; an identical call on another line survives" do
    input = """
    defmodule CredenceStreamDataFlatMapTwoCalls do
      def a(g, f), do: StreamData.flat_map(g, f)
      def b(g, f), do: StreamData.flat_map(g, f)
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapTwoCalls do
      def a(g, f), do: StreamData.bind(g, f)
      def b(g, f), do: StreamData.flat_map(g, f)
    end
    """

    confirm_fix(fix(input, {2, 31}), expected)
  end

  test "fixes on a line-only position when the line has exactly one candidate" do
    input = """
    defmodule CredenceStreamDataFlatMapLineOnly do
      def sized_lists do
        StreamData.flat_map(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapLineOnly do
      def sized_lists do
        StreamData.bind(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    confirm_fix(fix(input, 3), expected)
  end

  test "returns source unchanged when the column does not anchor on the call" do
    input = """
    defmodule CredenceStreamDataFlatMapBadCol do
      def gen(g, f) do
        StreamData.flat_map(g, f)
      end
    end
    """

    confirm_fix(fix(input, {3, 1}), input)
  end

  test "returns source unchanged when the flagged line does not exist" do
    input = """
    defmodule CredenceStreamDataFlatMapBadLine do
      def gen(g, f) do
        StreamData.flat_map(g, f)
      end
    end
    """

    confirm_fix(fix(input, {99, 16}), input)
  end

  test "returns source unchanged for the Elixir.-prefixed spelling" do
    input = """
    defmodule CredenceStreamDataFlatMapElixirPrefix do
      def gen(g, f), do: Elixir.StreamData.flat_map(g, f)
    end
    """

    confirm_fix(fix(input, {2, 40}), input)
  end

  test "returns source unchanged when no StreamData.flat_map present" do
    input = """
    defmodule CleanStreamDataExample do
      def gen, do: StreamData.integer(1..10)
    end
    """

    confirm_fix(fix(input, {2, 16}), input)
  end

  test "fixed flagship output is well-formed (parses)" do
    input = """
    defmodule CredenceStreamDataFlatMapParses do
      def sized_lists do
        StreamData.flat_map(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    assert valid_syntax?(fix(input, {3, 16}))
  end

  test "fixed flagship output compiles" do
    input = """
    defmodule CredenceStreamDataFlatMapCompiles do
      def sized_lists do
        StreamData.flat_map(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    assert compiles?(fix(input, {3, 16}))
  end

  test "end-to-end: the semantic phase fixes the flagship input and touches nothing else" do
    input = """
    defmodule CredenceStreamDataFlatMapE2E do
      def sized_lists do
        StreamData.flat_map(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapE2E do
      def sized_lists do
        StreamData.bind(StreamData.integer(1..10), fn len ->
          StreamData.list_of(StreamData.constant(len), length: len)
        end)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: two flagged calls on one line are both fixed via their own columns" do
    input = """
    defmodule CredenceStreamDataFlatMapTwoOnLineE2E do
      def a(g, f, h), do: {StreamData.flat_map(g, f), StreamData.flat_map(g, h)}
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapTwoOnLineE2E do
      def a(g, f, h), do: {StreamData.bind(g, f), StreamData.bind(g, h)}
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: a StreamData.flat_map spelling that resolves elsewhere via alias is left untouched" do
    input = """
    defmodule CredenceStreamDataFlatMapAliasShadowE2E do
      def a(g, f), do: StreamData.flat_map(g, f)

      def b(g, f) do
        alias CredenceStreamDataFlatMapAliasShadowE2E.CustomGen, as: StreamData
        StreamData.flat_map(g, f)
      end
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapAliasShadowE2E do
      def a(g, f), do: StreamData.bind(g, f)

      def b(g, f) do
        alias CredenceStreamDataFlatMapAliasShadowE2E.CustomGen, as: StreamData
        StreamData.flat_map(g, f)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the piped form is fixed" do
    input = """
    defmodule CredenceStreamDataFlatMapPipedE2E do
      def gen(inner, fun) do
        inner |> StreamData.flat_map(fun)
      end
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapPipedE2E do
      def gen(inner, fun) do
        inner |> StreamData.bind(fun)
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "end-to-end: the capture form is fixed" do
    input = """
    defmodule CredenceStreamDataFlatMapCaptureE2E do
      def combinator do
        &StreamData.flat_map/2
      end
    end
    """

    expected = """
    defmodule CredenceStreamDataFlatMapCaptureE2E do
      def combinator do
        &StreamData.bind/2
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "the fixed generator behaves as the hallucinated flat_map intended" do
    lists =
      StreamData.integer(1..10)
      |> StreamData.bind(fn len ->
        StreamData.list_of(StreamData.constant(len), length: len)
      end)
      |> Enum.take(20)

    assert Enum.all?(lists, fn list ->
             length(list) in 1..10 and Enum.all?(list, &(&1 == length(list)))
           end)
  end
end
