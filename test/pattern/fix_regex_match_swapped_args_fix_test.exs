defmodule Credence.Pattern.FixRegexMatchSwappedArgsFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixRegexMatchSwappedArgs
  alias Credence.RuleHelpers

  test "rewrites regex literal on the left of =~" do
    input = """
    defmodule Credence.Pattern.RegexMatchSwappedArgsLiteralFixture do
      def f, do: ~r/abc/ =~ "abc"
    end
    """

    expected = """
    defmodule Credence.Pattern.RegexMatchSwappedArgsLiteralFixture do
      def f, do: "abc" =~ ~r/abc/
    end
    """

    emitted = fix(FixRegexMatchSwappedArgs, input)

    confirm_fix(emitted, expected)
    assert RuleHelpers.compile_and_capture(emitted) == RuleHelpers.compile_and_capture(expected)
  end

  test "does not swap two regex operands into another crashing expression" do
    input = "~r/a/ =~ ~r/b/"

    emitted = fix(FixRegexMatchSwappedArgs, input)

    confirm_fix(emitted, input)
    confirm_fix(fix(FixRegexMatchSwappedArgs, emitted), emitted)
    assert clean?(FixRegexMatchSwappedArgs, input)
  end

  test "does not claim an operand swap repairs an unconstrained right operand" do
    input = "def f(x), do: ~r/a/ =~ x"

    confirm_fix(fix(FixRegexMatchSwappedArgs, input), input)
    assert clean?(FixRegexMatchSwappedArgs, input)
  end

  test "rewrites module attribute regex on the left of =~" do
    input = """
    defmodule M do
      @re ~r/^[a-z]+$/
      def f, do: @re =~ "abc"
    end
    """

    expected = """
    defmodule M do
      @re ~r/^[a-z]+$/
      def f, do: "abc" =~ @re
    end
    """

    confirm_fix(fix(FixRegexMatchSwappedArgs, input), expected)
  end

  test "does not touch an attribute that is later reassigned to a non-regex" do
    input = """
    defmodule M do
      @re ~r/x/
      def broken(s), do: @re =~ s
      @re "hello"
      def valid(s), do: @re =~ s
    end
    """

    confirm_fix(fix(FixRegexMatchSwappedArgs, input), input)
  end

  test "does not touch attribute =~ inside a quote block" do
    input = """
    defmodule M do
      @re ~r/x/

      defmacro m(s) do
        quote do
          @re =~ unquote(s)
        end
      end
    end
    """

    confirm_fix(fix(FixRegexMatchSwappedArgs, input), input)
  end
end
