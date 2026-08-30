defmodule Credence.Pattern.FixRegexMatchSwappedArgsCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.FixRegexMatchSwappedArgs

  # ── FLAGGED ─────────────────────────────────────────────────────────────

  test "flags regex literal on the left of =~" do
    code = """
    defmodule M do
      def f, do: ~r/abc/ =~ "abc"
    end
    """

    assert flagged?(FixRegexMatchSwappedArgs, code)
  end

  test "flags module attribute regex on the left of =~" do
    code = """
    defmodule M do
      @re ~r/^[a-z]+$/
      def f, do: @re =~ "abc"
    end
    """

    assert flagged?(FixRegexMatchSwappedArgs, code)
  end

  test "flags regex literal on the left even inside a quote block" do
    code = """
    defmodule M do
      defmacro m(_x) do
        quote do
          ~r/abc/ =~ "abc"
        end
      end
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

  test "leaves attribute alone when it is later reassigned to a non-regex" do
    # After `@re "hello"`, `@re =~ x` is a VALID substring check — the swap
    # would flip its answer (`"hello" =~ "ell"` is true, `"ell" =~ "hello"`
    # is false). One non-regex assignment disqualifies the name everywhere.
    code = """
    defmodule M do
      @re ~r/x/
      def broken(s), do: @re =~ s
      @re "hello"
      def valid(s), do: @re =~ s
    end
    """

    assert clean?(FixRegexMatchSwappedArgs, code)
  end

  test "leaves attribute alone when assigned a non-regex in another module in the file" do
    code = """
    defmodule A do
      @re ~r/x/
      def f(s), do: @re =~ s
    end

    defmodule B do
      @re "hello"
      def f(s), do: @re =~ s
    end
    """

    assert clean?(FixRegexMatchSwappedArgs, code)
  end

  test "leaves all attributes alone when Module.put_attribute appears in the file" do
    # A dynamic write can give the attribute a non-regex value this static
    # analysis cannot see.
    code = """
    defmodule M do
      @re ~r/x/
      Module.put_attribute(__MODULE__, :re, "hello")
      def f(s), do: @re =~ s
    end
    """

    assert clean?(FixRegexMatchSwappedArgs, code)
  end

  test "leaves all attributes alone when Module.register_attribute appears in the file" do
    code = """
    defmodule M do
      Module.register_attribute(__MODULE__, :re, accumulate: true)
      @re ~r/x/
      def f(s), do: @re =~ s
    end
    """

    assert clean?(FixRegexMatchSwappedArgs, code)
  end

  test "leaves attribute =~ inside a quote block alone" do
    # Quoted code resolves `@re` in the module it is injected into — this
    # file's `@re` value says nothing about it.
    code = """
    defmodule M do
      @re ~r/x/
      defmacro m(s) do
        quote do
          @re =~ unquote(s)
        end
      end
    end
    """

    assert clean?(FixRegexMatchSwappedArgs, code)
  end

  test "leaves attribute assigned a runtime-built regex alone" do
    # `Regex.compile!/1` does return a regex, but the rule only trusts ~r
    # literals; anything else counts as a disqualifying assignment.
    code = """
    defmodule M do
      @re Regex.compile!("x")
      def f(s), do: @re =~ s
    end
    """

    assert clean?(FixRegexMatchSwappedArgs, code)
  end
end
