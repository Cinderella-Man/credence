defmodule Credence.Syntax.CloseUnclosedBraceAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.CloseUnclosedBrace

  defp analyze(code), do: CloseUnclosedBrace.analyze(code)

  test "flags code with unclosed tuple brace before end" do
    code = """
    defmodule Example do
      use GenServer

      def init(_opts) do
        {:ok, %{key: "value"}
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 5}}] = analyze(code)
  end

  test "flags code with unclosed map brace before end" do
    code = """
    defmodule Example do
      def foo do
        %{key: "value"
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 3}}] = analyze(code)
  end

  test "flags nested openings that need more than one closing brace" do
    code = """
    defmodule Example do
      def foo do
        {:ok, %{a: 1
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 3}}] = analyze(code)
  end

  test "flags a nesting at the @max_braces backstop — five closing braces" do
    code = """
    defmodule Example do
      def foo do
        {:ok, %{a: %{b: %{c: %{d: 1
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 3}}] = analyze(code)
  end

  test "flags a literal spread over several lines" do
    code = """
    defmodule Example do
      def foo do
        {:ok,
         1
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 3}}] = analyze(code)
  end

  test "flags an unclosed struct literal" do
    code = """
    defmodule Example do
      def foo do
        %User{name: "a"
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 3}}] = analyze(code)
  end

  test "leaves properly closed braces alone" do
    code = """
    defmodule Example do
      def init(_opts) do
        {:ok, %{key: "value"}}
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves code without braces alone" do
    code = """
    defmodule Example do
      def foo do
        IO.puts("hello")
      end
    end
    """

    assert analyze(code) == []
  end

  # --- deliberately skipped: no single faithful placement for the `}` ---

  test "no issue when the closing brace could belong on either of two lines" do
    # `}` after `IO.puts(x)` would swallow the call into the tuple, and the
    # parser cannot tell us that the author meant it one line earlier — so the
    # rule refuses rather than guessing.
    code = """
    defmodule Example do
      def foo do
        x = {1, 2
        IO.puts(x)
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue when the next line's leading operator makes both placements parse" do
    # `x = {1, 2}` piped into IO.inspect and the tuple `{1, 2 |> IO.inspect()}`
    # both parse, so there is no single faithful placement — the rule refuses
    # rather than guessing.
    code = """
    defmodule Example do
      def foo do
        x = {1, 2
        |> IO.inspect()
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue when the literal's last line ends with a dangling comma" do
    # Elixir accepts a trailing comma, so closing here would parse as the
    # one-element `{:ok}` — silently dropping the missing element.
    code = """
    defmodule Example do
      def foo do
        {:ok,
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue beyond the @max_braces backstop — six closing braces needed" do
    # Deeper than the backstop is a degenerate input, not a target: the rule
    # stays silent rather than stacking ever more braces onto one line.
    code = """
    defmodule Example do
      def foo do
        {:ok, %{a: %{b: %{c: %{d: %{e: 1
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue when two separate literals are left unclosed" do
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

    assert analyze(code) == []
  end

  test "no issue when the mismatched end sits on the opening line" do
    code = """
    defmodule Example do
      def foo do x = {1, 2 end
    end
    """

    assert analyze(code) == []
  end

  test "no issue when a comment would swallow the inserted brace" do
    code = """
    defmodule Example do
      def foo do
        x = {1, 2 # oops
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue for an unrelated syntax error" do
    code = """
    defmodule Example do
      def foo do
        x = [1, 2
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue for a brace that only appears inside a string" do
    code = """
    defmodule Example do
      def foo do
        IO.puts("{")
      end
    end
    """

    assert analyze(code) == []
  end
end
