defmodule Credence.Pattern.FixRegexMatchSwappedArgsCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixRegexMatchSwappedArgs

  # ── FLAGGED ─────────────────────────────────────────────────────────────

  test "flags regex literal on the left of =~" do
    code = """
    defmodule M do
      def f(x), do: ~r/abc/ =~ x
    end
    """

    assert flagged?(FixRegexMatchSwappedArgs, code)
  end

  test "flags module attribute regex on the left of =~" do
    code = """
    defmodule M do
      @re ~r/^[a-z]+$/
      def f(x), do: @re =~ x
    end
    """

    assert flagged?(FixRegexMatchSwappedArgs, code)
  end

  # ── NOT FLAGGED ─────────────────────────────────────────────────────────

  test "leaves string on the left of =~ alone" do
    code = """
    defmodule M do
      def f(x), do: x =~ ~r/abc/
    end
    """

    assert clean?(FixRegexMatchSwappedArgs, code)
  end

  test "leaves two strings alone" do
    code = """
    defmodule M do
      def f(x), do: x =~ "abc"
    end
    """

    assert clean?(FixRegexMatchSwappedArgs, code)
  end

  test "leaves non-regex module attribute on the left alone" do
    code = """
    defmodule M do
      @pattern "hello"
      def f(x), do: @pattern =~ x
    end
    """

    assert clean?(FixRegexMatchSwappedArgs, code)
  end
end
