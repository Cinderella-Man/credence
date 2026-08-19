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
