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

  test "reports the line the literal starts on, not the innermost opening" do
    # The parser names the *innermost* `{` it was still holding — line 4 here.
    # The literal the author has to close starts on line 3, and that is the
    # line the issue must point at.
    code = """
    defmodule Example do
      def foo do
        x = {1,
            %{a: 2
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 3}}] = analyze(code)
  end

  test "flags a multi-line map whose opening line is no competing placement" do
    # The positive control for the "is there a competing placement?" probe.
    # Line 3 holds the `%{` and nothing else, so the rule really does try
    # putting the `}` there — and `%{}` on line 3 strands `a: 1,` / `b: 2`,
    # which does not parse, so the probe declines and the repair stands.
    # Every other flagging test in this file either has no earlier line to
    # scan or has one ending in `,` (skipped before the probe runs), so
    # without this test a probe that cried "ambiguous" at every line would
    # leave the whole battery green.
    code = """
    defmodule Example do
      def foo do
        %{
          a: 1,
          b: 2
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 3}}] = analyze(code)
  end

  test "no issue when a nesting that opens on two lines has a competing placement" do
    # Two readings parse and mean different things: both braces at the end
    # (`{1 ++ %{a: 2}}`, a one-element tuple) or one brace on line 3 and one on
    # line 4 (`{1} ++ %{a: 2}`). Line 3 is before the `{` the parser names, so
    # the rule must still consider it before committing.
    code = """
    defmodule Example do
      def foo do
        x = {1
        ++ %{a: 2
      end
    end
    """

    assert analyze(code) == []
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

  test "no issue when the braces could be split across two lines" do
    # Closing both on the last line gives `{1, {2, {3}, 5}}`; closing the
    # inner one a line up and the outer at the end gives `{1, {2, {3}}, 5}`.
    # Both parse and mean different things, so the rule refuses rather than
    # guessing.
    code = """
    defmodule Example do
      def foo do
        x = {1, {2, {3
        }, 5
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue when the literal opens on the line the brace would be added to" do
    # `x = {1, 2} |> IO.inspect()` and `x = {1, 2 |> IO.inspect()}` both parse
    # and mean different things. There is no earlier line here, so the rival
    # placement sits inside the same line — the rule must refuse it just as it
    # refuses the two-line spelling of the same doubt.
    code = """
    defmodule Example do
      def foo do
        x = {1, 2 |> IO.inspect()
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue when a rival placement sits inside the literal's last line" do
    # The `}` could belong after the `2` rather than at the end of the line;
    # the line above ends in `,` and is not a candidate, so only a placement
    # weighed within the last line itself can see this ambiguity.
    code = """
    defmodule Example do
      def foo do
        x = {1,
        2 |> IO.inspect()
      end
    end
    """

    assert analyze(code) == []
  end

  test "no issue when an earlier line's comment ends in a comma" do
    # A trailing comma pins the next line inside the literal only when it is a
    # comma in code. This one is inside a comment, and the comment also
    # swallows any `}` appended to that line — the same doubt the rule refuses
    # a line ending in `# }` for.
    code = """
    defmodule Example do
      def foo do
        x = {1 # oops,
        |> g()
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
    # There is no line between the `{` and the `end` to append the `}` to, so
    # `target_line/3` finds no target and the rule refuses. That empty scan
    # range is what enforces "the `end` must be on a later line" — this test
    # pins the behaviour, not any one guard expression.
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

  test "leaves a source that parses alone, brace inside a string and all" do
    # This pins "a parsing source is left alone", nothing more: `detect/1` asks
    # the parser for a mismatched delimiter, gets none, and returns before any
    # brace reasoning happens — the same reason "leaves code without braces
    # alone" passes. The `{` inside the string is never examined, so this is
    # not masking coverage; the four tests below the next comment are.
    code = """
    defmodule Example do
      def foo do
        IO.puts("{")
      end
    end
    """

    assert analyze(code) == []
  end

  # --- a `{` inside a string, heredoc or comment is never the unclosed one ---
  #
  # The test above only shows that a source which parses is left alone. These
  # feed the rule a source that really is missing a `}` *and* carries a `{`
  # inside a string, heredoc or comment, so the reported literal has to be the
  # one in code.

  test "reports the literal in code, not a brace inside a string on an earlier line" do
    # Line 3 holds a `{` inside a string; line 4 opens the literal that is
    # actually unclosed. The issue must name line 4.
    code = """
    defmodule Example do
      def foo do
        s = "{"
        x = {1, 2
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 4}}] = analyze(code)
  end

  test "counts only the braces the parser sees, not six more inside a string" do
    # One `}` is missing. A rule that counted `{` textually would want seven —
    # past the @max_braces backstop — and report nothing at all.
    code = """
    defmodule Example do
      def foo do
        x = %{a: "{{{{{{"
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 3}}] = analyze(code)
  end

  test "reports the literal in code, not a brace inside a heredoc above it" do
    # The heredoc on lines 3-5 contains a `{`; the literal that is unclosed
    # opens on line 7.
    code = """
    defmodule Example do
      def foo do
        s = \"""
        {
        \"""

        x = {1, 2
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 7}}] = analyze(code)
  end

  test "reports the literal in code, not a brace inside a comment above it" do
    code = """
    defmodule Example do
      def foo do
        # {
        x = {1, 2
      end
    end
    """

    assert [%Issue{rule: :close_unclosed_brace, meta: %{line: 4}}] = analyze(code)
  end
end
