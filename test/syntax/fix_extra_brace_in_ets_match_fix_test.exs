defmodule Credence.Syntax.FixExtraBraceInEtsMatchFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixExtraBraceInEtsMatch

  defp analyze(code), do: FixExtraBraceInEtsMatch.analyze(code)
  defp fix(code), do: FixExtraBraceInEtsMatch.fix(code)

  test "drops the extra brace before the closing paren" do
    input = """
    defmodule Example do
      def lookup(table, name) do
        :ets.match(table, {{name, :"$1"}, :"$2"}})
      end
    end
    """

    expected = """
    defmodule Example do
      def lookup(table, name) do
        :ets.match(table, {{name, :"$1"}, :"$2"})
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "repairs any :ets. function, not just match" do
    input = ~S':ets.match_object(table, {name, :"$1"}})'

    expected = ~S':ets.match_object(table, {name, :"$1"})'

    confirm_fix(fix(input), expected)
  end

  test "repairs a call spread over several lines" do
    input = """
    :ets.match(table,
      {{name, :"$1"}, :"$2"}})
    """

    expected = """
    :ets.match(table,
      {{name, :"$1"}, :"$2"})
    """

    confirm_fix(fix(input), expected)
  end

  test "touches nothing else in the file" do
    input = """
    defmodule Example do
      def send_msg(pid) do
        send(pid, {:msg, %{name: "x"}})
      end

      def lookup(table, name) do
        :ets.match(table, {{name, :"$1"}, :"$2"}})
      end
    end
    """

    expected = """
    defmodule Example do
      def send_msg(pid) do
        send(pid, {:msg, %{name: "x"}})
      end

      def lookup(table, name) do
        :ets.match(table, {{name, :"$1"}, :"$2"})
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = """
    defmodule Example do
      def lookup(table, name) do
        :ets.match(table, {{name, :"$1"}, :"$2"}})
      end
    end
    """

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = """
    defmodule Example do
      def lookup(table, name) do
        :ets.match(table, {{name, :"$1"}, :"$2"}})
      end
    end
    """

    assert valid_syntax?(fix(code))
  end

  # --- columns are codepoints: text before the brace must not shift the cut ---

  test "cuts the right brace with a precomposed accent earlier on the line" do
    input = """
    defmodule Example do
      def lookup(table) do
        :ets.match(table, {{"café", :"$1"}, :"$2"}})
      end
    end
    """

    expected = """
    defmodule Example do
      def lookup(table) do
        :ets.match(table, {{"café", :"$1"}, :"$2"})
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "cuts the right brace with a combining accent earlier on the line" do
    # `e` + U+0301 is two codepoints but one grapheme.
    input = """
    defmodule Example do
      def lookup(table) do
        :ets.match(table, {{"cafe#{<<0x301::utf8>>}", :"$1"}, :"$2"}})
      end
    end
    """

    expected = """
    defmodule Example do
      def lookup(table) do
        :ets.match(table, {{"cafe#{<<0x301::utf8>>}", :"$1"}, :"$2"})
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "cuts the right brace with a multi-codepoint emoji and a flag earlier on the line" do
    input = """
    defmodule Example do
      def lookup(table) do
        :ets.match(table, {{"👨‍👩‍👧🇵🇱", :"$1"}, :"$2"}})
      end
    end
    """

    expected = """
    defmodule Example do
      def lookup(table) do
        :ets.match(table, {{"👨‍👩‍👧🇵🇱", :"$1"}, :"$2"})
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  # --- the cases the check deliberately skips are left byte-for-byte alone ---

  test "does not modify already-valid code" do
    code = """
    defmodule Example do
      def lookup(table, name) do
        :ets.match(table, {{name, :"$1"}, :"$2"})
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "leaves a valid nested-tuple pattern ending in the same bytes untouched" do
    code = ~S':ets.match(table, {{name, :"$1"}, {:"$2"}})'

    confirm_fix(fix(code), code)
  end

  test "leaves a valid call ending in the same bytes in a file broken elsewhere untouched" do
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

    confirm_fix(fix(code), code)
  end

  test "leaves an extra brace in a non-:ets. call untouched" do
    code = "send(pid, {:a, 1}})"

    confirm_fix(fix(code), code)
  end

  test "leaves more than one extra brace untouched" do
    code = ~S':ets.match(table, {{name, :"$1"}, :"$2"}}})'

    confirm_fix(fix(code), code)
  end

  test "leaves a stray brace that does not close a nested tuple untouched" do
    code = ":ets.match(table, {a, b}, c})"

    confirm_fix(fix(code), code)
  end

  test "repairs the reported ETS error while another syntax error remains" do
    input = """
    defmodule Example do
      def lookup(t) do
        :ets.match(t, {{:"$1"}, :"$2"}})
      end

      def other do
        x = [1, 2
      end
    end
    """

    expected = """
    defmodule Example do
      def lookup(t) do
        :ets.match(t, {{:"$1"}, :"$2"})
      end

      def other do
        x = [1, 2
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "repairs two malformed ETS calls incrementally" do
    input = """
    :ets.match(first, {{:"$1"}, :"$2"}})
    :ets.match(second, {{:"$3"}, :"$4"}})
    """

    after_first = """
    :ets.match(first, {{:"$1"}, :"$2"})
    :ets.match(second, {{:"$3"}, :"$4"}})
    """

    expected = """
    :ets.match(first, {{:"$1"}, :"$2"})
    :ets.match(second, {{:"$3"}, :"$4"})
    """

    confirm_fix(fix(input), after_first)
    confirm_fix(fix(fix(input)), expected)
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

  test "leaves the bad bytes inside a string untouched" do
    code = """
    defmodule Example do
      def foo do
        IO.puts(~S|:ets.match(t, {{a}, :"$2"}})|)
        x = [1, 2
      end
    end
    """

    confirm_fix(fix(code), code)
  end
end
