defmodule Credence.Syntax.FixExtraBraceInEtsMatchAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixExtraBraceInEtsMatch

  defp analyze(code), do: FixExtraBraceInEtsMatch.analyze(code)

  test "flags an extra brace before the closing paren of :ets.match" do
    code = """
    defmodule Example do
      def lookup(table, name) do
        :ets.match(table, {{name, :"$1"}, :"$2"}})
      end
    end
    """

    assert [%Issue{rule: :fix_extra_brace_in_ets_match, meta: %{line: 3}}] = analyze(code)
  end

  test "flags any :ets. function, not just match" do
    code = ~S':ets.match_object(table, {name, :"$1"}})'

    assert [%Issue{rule: :fix_extra_brace_in_ets_match, meta: %{line: 1}}] = analyze(code)
  end

  test "flags at the brace's line when the call spans several lines" do
    code = """
    :ets.match(table,
      {{name, :"$1"}, :"$2"}})
    """

    assert [%Issue{rule: :fix_extra_brace_in_ets_match, meta: %{line: 2}}] = analyze(code)
  end

  test "leaves properly closed ETS patterns alone" do
    code = """
    defmodule Example do
      def lookup(table, name) do
        :ets.match(table, {{name, :"$1"}, :"$2"})
      end
    end
    """

    assert analyze(code) == []
  end

  test "leaves code without ETS calls alone" do
    code = """
    defmodule Example do
      def foo do
        IO.puts("hello")
      end
    end
    """

    assert analyze(code) == []
  end

  # --- columns are codepoints: text before the brace must not shift it ---

  test "flags with a precomposed accent earlier on the line" do
    code = """
    defmodule Example do
      def lookup(table) do
        :ets.match(table, {{"café", :"$1"}, :"$2"}})
      end
    end
    """

    assert [%Issue{rule: :fix_extra_brace_in_ets_match, meta: %{line: 3}}] = analyze(code)
  end

  test "flags with a combining accent earlier on the line" do
    # `e` + U+0301 is two codepoints but one grapheme — counting graphemes here
    # would put the column one place to the left.
    code = """
    defmodule Example do
      def lookup(table) do
        :ets.match(table, {{"cafe#{<<0x301::utf8>>}", :"$1"}, :"$2"}})
      end
    end
    """

    assert [%Issue{rule: :fix_extra_brace_in_ets_match, meta: %{line: 3}}] = analyze(code)
  end

  test "flags with a multi-codepoint emoji and a flag earlier on the line" do
    code = """
    defmodule Example do
      def lookup(table) do
        :ets.match(table, {{"👨‍👩‍👧🇵🇱", :"$1"}, :"$2"}})
      end
    end
    """

    assert [%Issue{rule: :fix_extra_brace_in_ets_match, meta: %{line: 3}}] = analyze(code)
  end

  # --- the bytes are ambiguous: only the parser can tell these apart ---

  test "no issue for a valid nested-tuple pattern ending in the same bytes" do
    # `:"$2"}})` here closes `{:"$2"}` and then the outer tuple — a text scan
    # for those bytes would break perfectly good code.
    code = ~S':ets.match(table, {{name, :"$1"}, {:"$2"}})'

    assert analyze(code) == []
  end

  test "no issue for a valid call ending in the same bytes in a file broken elsewhere" do
    # The parse error is the malformed `def` head; `send/2` is fine and must
    # keep its bytes.
    code = """
    defmodule Example do
      def broken(a, b, do
        a + b
      end

      def send_msg(pid) do
        send(pid, {:msg, %{name: "x"}})
      end
    end
    """

    assert analyze(code) == []
  end

  # --- deliberately skipped: outside the shape this rule can repair ---

  test "no issue for an extra brace in a call that is not :ets." do
    code = "send(pid, {:a, 1}})"

    assert analyze(code) == []
  end

  test "no issue when more than one brace is extra" do
    code = ~S':ets.match(table, {{name, :"$1"}, :"$2"}}})'

    assert analyze(code) == []
  end

  test "no issue when the stray brace does not close a nested tuple argument" do
    code = ":ets.match(table, {a, b}, c})"

    assert analyze(code) == []
  end

  test "no issue when the file is also broken somewhere else" do
    code = """
    defmodule Example do
      def lookup(t) do
        :ets.match(t, {{:"$1"}, :"$2"}})
      end

      def other do
        x = [1, 2
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

  test "no issue for the bad bytes appearing only inside a string" do
    code = """
    defmodule Example do
      def foo do
        IO.puts(~S|:ets.match(t, {{a}, :"$2"}})|)
        x = [1, 2
      end
    end
    """

    assert analyze(code) == []
  end
end
