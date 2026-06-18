defmodule Credence.Pattern.HallucinatedGuardFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.HallucinatedGuard

  describe "is_pos_integer → is_integer and > 0" do
    test "bare call" do
      confirm_fix(fix(HallucinatedGuard, "is_pos_integer(x)"), "is_integer(x) and x > 0")
    end

    test "in a guard" do
      confirm_fix(
        fix(HallucinatedGuard, "def foo(x) when is_pos_integer(x), do: x"),
        "def foo(x) when is_integer(x) and x > 0, do: x"
      )
    end
  end

  describe "is_non_neg_integer → is_integer and >= 0" do
    test "bare call" do
      confirm_fix(fix(HallucinatedGuard, "is_non_neg_integer(x)"), "is_integer(x) and x >= 0")
    end

    test "in a guard" do
      confirm_fix(
        fix(HallucinatedGuard, "def foo(x) when is_non_neg_integer(x), do: x"),
        "def foo(x) when is_integer(x) and x >= 0, do: x"
      )
    end
  end

  describe "is_neg_integer → is_integer and < 0" do
    test "bare call" do
      confirm_fix(fix(HallucinatedGuard, "is_neg_integer(x)"), "is_integer(x) and x < 0")
    end

    test "in a guard" do
      confirm_fix(
        fix(HallucinatedGuard, "def foo(x) when is_neg_integer(x), do: x"),
        "def foo(x) when is_integer(x) and x < 0, do: x"
      )
    end
  end

  describe "is_non_pos_integer → is_integer and <= 0" do
    test "bare call" do
      confirm_fix(fix(HallucinatedGuard, "is_non_pos_integer(x)"), "is_integer(x) and x <= 0")
    end

    test "in a guard" do
      confirm_fix(
        fix(HallucinatedGuard, "def foo(x) when is_non_pos_integer(x), do: x"),
        "def foo(x) when is_integer(x) and x <= 0, do: x"
      )
    end
  end

  describe "no-ops" do
    test "valid guards unchanged" do
      code = "def foo(x) when is_integer(x) and x > 0, do: x"

      confirm_fix(fix(HallucinatedGuard, code), code)
    end

    test "regular function calls unchanged" do
      code = "Enum.map(list, &is_integer/1)"

      confirm_fix(fix(HallucinatedGuard, code), code)
    end
  end

  # A name DEFINED via defguard/defguardp is a real guard — the fix must leave it
  # alone everywhere. Previously it rewrote the definition head into invalid
  # syntax (`defguardp is_integer(x) and x > 0 when ...`) and unrolled call sites.
  describe "leaves a module-defined guard untouched" do
    test "defguardp definition head is not mangled" do
      code = """
      defmodule M do
        defguardp is_pos_integer(term) when is_integer(term) and term > 0
      end
      """

      confirm_fix(fix(HallucinatedGuard, code), code)
    end

    test "public defguard definition head is not mangled" do
      code = """
      defmodule M do
        defguard is_pos_integer(num) when is_integer(num) and num > 0
      end
      """

      confirm_fix(fix(HallucinatedGuard, code), code)
    end

    test "definition and its call sites are both left intact (the tucan shape)" do
      code = """
      defmodule M do
        defguardp is_pos_integer(term) when is_integer(term) and term > 0

        def set_width(vl, width) when is_pos_integer(width), do: vl
        def set_height(vl, height) when is_pos_integer(height), do: vl
      end
      """

      confirm_fix(fix(HallucinatedGuard, code), code)
    end

    test "multiple defined guards (the pfx shape) are left intact" do
      code = """
      defmodule M do
        defguardp is_non_neg_integer(n) when is_integer(n) and n >= 0
        defguardp is_pos_integer(n) when is_integer(n) and n > 0

        def f(x) when is_non_neg_integer(x), do: x
        def g(x) when is_pos_integer(x), do: x
      end
      """

      confirm_fix(fix(HallucinatedGuard, code), code)
    end
  end

  describe "fixes only the genuinely-hallucinated guard in a mixed module" do
    test "defined is_pos_integer kept; undefined is_neg_integer rewritten" do
      input = """
      defmodule M do
        defguardp is_pos_integer(n) when is_integer(n) and n > 0

        def f(x) when is_pos_integer(x), do: x
        def g(x) when is_neg_integer(x), do: x
      end
      """

      expected = """
      defmodule M do
        defguardp is_pos_integer(n) when is_integer(n) and n > 0

        def f(x) when is_pos_integer(x), do: x
        def g(x) when is_integer(x) and x < 0, do: x
      end
      """

      confirm_fix(fix(HallucinatedGuard, input), expected)
    end

    test "a defguard at a different arity does not protect the /1 call" do
      input = """
      defmodule M do
        defguardp is_pos_integer(a, b) when a > 0 and b > 0
        def f(x) when is_pos_integer(x), do: x
      end
      """

      expected = """
      defmodule M do
        defguardp is_pos_integer(a, b) when a > 0 and b > 0
        def f(x) when is_integer(x) and x > 0, do: x
      end
      """

      confirm_fix(fix(HallucinatedGuard, input), expected)
    end
  end

  # The fixed output must always be a real Elixir guard expression, never an
  # invalid `defguard` head.
  describe "output validity" do
    test "no defguard head is rewritten into an operator expression" do
      for guard <- ~w(is_pos_integer is_non_neg_integer is_neg_integer is_non_pos_integer) do
        code = """
        defmodule M do
          defguardp #{guard}(n) when is_integer(n) and n > 0
          def f(x) when #{guard}(x), do: x
        end
        """

        fixed = fix(HallucinatedGuard, code)
        assert {:ok, _} = Code.string_to_quoted(fixed)
        # the defguard head atom survives verbatim — never split into `... and ...`
        assert fixed =~ "defguardp #{guard}(n)"
      end
    end
  end
end
