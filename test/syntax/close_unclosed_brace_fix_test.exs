defmodule Credence.Syntax.CloseUnclosedBraceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.CloseUnclosedBrace

  defp analyze(code), do: CloseUnclosedBrace.analyze(code)
  defp fix(code), do: CloseUnclosedBrace.fix(code)

  test "fixes unclosed tuple brace before end" do
    input = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    expected = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    assert valid_syntax?(fix(code))
  end

  test "does not modify already-valid code" do
    code = """
    defmodule Example do
      def init(_opts) do
        {:ok, %{key: "value"}}
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "fixes unclosed map brace before end" do
    input = """
    defmodule Example do
      def foo do
        %{key: "value"
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        %{key: "value"}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "closes a literal spread over several lines on its last line" do
    input = """
    defmodule Example do
      def foo do
        {:ok,
         1
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        {:ok,
         1}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "closes a multi-line map on its last entry" do
    input = """
    defmodule Example do
      def foo do
        %{
          a: 1,
          b: 2
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        %{
          a: 1,
          b: 2}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "adds as many closing braces as the nesting needs" do
    input = """
    defmodule Example do
      def foo do
        {:ok, %{a: %{b: 1
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        {:ok, %{a: %{b: 1}}}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "closes an unclosed struct literal" do
    input = """
    defmodule Example do
      def foo do
        %User{name: "a"
      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        %User{name: "a"}
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "closes a tuple inside an fn body" do
    input = """
    defmodule Example do
      def foo(list) do
        Enum.map(list, fn x ->
          {x, x
        end)
      end
    end
    """

    expected = """
    defmodule Example do
      def foo(list) do
        Enum.map(list, fn x ->
          {x, x}
        end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "skips a blank line and closes on the literal's last content line" do
    input = """
    defmodule Example do
      def foo do
        x = {1, 2

      end
    end
    """

    expected = """
    defmodule Example do
      def foo do
        x = {1, 2}

      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  # --- the cases the check deliberately skips are left byte-for-byte alone ---

  test "leaves an ambiguous placement untouched" do
    code = """
    defmodule Example do
      def foo do
        x = {1, 2
        IO.puts(x)
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an operator-continuation ambiguity untouched" do
    # Both placements parse and mean different things: `x = {1, 2}` piped
    # into IO.inspect, or the tuple `{1, 2 |> IO.inspect()}`. The rule must
    # refuse rather than silently commit one of the two meanings.
    code = """
    defmodule Example do
      def foo do
        x = {1, 2
        |> IO.inspect()
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a placement split across two lines untouched" do
    # Two readings of the truncated source parse and mean different things:
    # both missing braces at the end (`{1, {2, {3}, 5}}`), or the inner one a
    # line up and only the outer at the end (`{1, {2, {3}}, 5}`). The rule
    # must refuse rather than silently commit one of the two meanings.
    code = """
    defmodule Example do
      def foo do
        x = {1, {2, {3
        }, 5
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a nesting that opens on two lines untouched" do
    # The parser names only the innermost `{` still open — line 4 here — so
    # line 3, where the outer `{` sits, is the first line a competing `}` could
    # belong to. Both readings parse and differ: `{1 ++ %{a: 2}}` is a
    # one-element tuple, `{1} ++ %{a: 2}` concatenates a tuple and a map. The
    # rule must refuse rather than silently commit one of them.
    code = """
    defmodule Example do
      def foo do
        x = {1
        ++ %{a: 2
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an earlier line that swallows the brace in a comment untouched" do
    # Appending a `}` to line 3 puts it inside the comment, so we cannot tell
    # whether the brace belonged there — the same doubt as a competing
    # placement, and refused for the same reason. (Committing would turn the
    # author's likely `{1} |> g()` into `{1 |> g()}`.)
    code = """
    defmodule Example do
      def foo do
        x = {1 # }
        |> g()
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "scans a long literal without a blow-up in reparses" do
    # The uniqueness scan tries the missing braces on every earlier line of the
    # literal, and each try reparses the whole file. Trying every *count* on
    # every line made that 25 whole-file reparses per line: an 800-line literal
    # took ~2.2s. Only the shares of the braces the repair actually needed can
    # compete, so the real bound is a couple of reparses per line — ~0.19s for
    # the same input. The limit below sits between the two, with room for a
    # loaded machine on either side.
    # 400 entries, each spread over two lines so no line ends in `,` but the
    # last — which would be a dangling comma and refused before the scan runs.
    entries =
      Enum.map_join(1..400, "\n", fn i ->
        "      k#{i}:\n        #{i}#{if i < 400, do: ",", else: ""}"
      end)

    code = "defmodule Example do\n  def foo do\n    x = %{\n" <> entries <> "\n  end\nend\n"

    best = Enum.min(for _ <- 1..3, do: elem(:timer.tc(fn -> fix(code) end), 0))

    assert fix(code) != code
    assert best < 1_000_000, "scan took #{div(best, 1000)}ms, expected well under 1000ms"
  end

  test "leaves a dangling comma untouched" do
    code = """
    defmodule Example do
      def foo do
        {:ok,
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves two unclosed literals untouched" do
    code = """
    defmodule Example do
      def foo do
        {:ok, 1
      end

      def bar do
        %{a: 1
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a same-line mismatched end untouched" do
    code = """
    defmodule Example do
      def foo do x = {1, 2 end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a brace hidden in a trailing comment untouched" do
    code = """
    defmodule Example do
      def foo do
        x = {1, 2 # oops
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves an unrelated syntax error untouched" do
    code = """
    defmodule Example do
      def foo do
        x = [1, 2
      end
    end
    """

    confirm_fix(fix(code), code)
  end
end
