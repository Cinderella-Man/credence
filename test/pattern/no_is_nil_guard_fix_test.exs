defmodule Credence.Pattern.NoIsNilGuardFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoIsNilGuard

  # ── sole guard, param unused ───────────────────────────────────

  describe "sole guard, param unused" do
    test "def one-liner" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x) when is_nil(x), do: :bar"),
        "def foo(nil), do: :bar"
      )
    end

    test "defp one-liner" do
      confirm_fix(
        fix(NoIsNilGuard, "defp foo(x) when is_nil(x), do: :bar"),
        "defp foo(nil), do: :bar"
      )
    end

    test "multi-param, is_nil on first" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x, y) when is_nil(x), do: y"),
        "def foo(nil, y), do: y"
      )
    end

    test "multi-param, is_nil on second" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x, y) when is_nil(y), do: x"),
        "def foo(x, nil), do: x"
      )
    end

    test "three params, is_nil on middle" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x, y, z) when is_nil(y), do: {x, z}"),
        "def foo(x, nil, z), do: {x, z}"
      )
    end
  end

  # ── combined guard with and ────────────────────────────────────

  describe "combined guard with and" do
    test "is_nil first, other guard kept" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x, y) when is_nil(x) and is_binary(y), do: :ok"),
        "def foo(nil, y) when is_binary(y), do: :ok"
      )
    end

    test "is_nil second, other guard kept" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x, y) when is_binary(y) and is_nil(x), do: :ok"),
        "def foo(nil, y) when is_binary(y), do: :ok"
      )
    end

    test "both params nil, guard dropped entirely" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x, y) when is_nil(x) and is_nil(y), do: :ok"),
        "def foo(nil, nil), do: :ok"
      )
    end

    test "is_nil plus two other guards" do
      confirm_fix(
        fix(
          NoIsNilGuard,
          "def foo(x, y, z) when is_nil(x) and is_binary(y) and is_integer(z), do: :ok"
        ),
        "def foo(nil, y, z) when is_binary(y) and is_integer(z), do: :ok"
      )
    end

    test "nil-tested param used by the remaining guard stays bound" do
      code = """
      defmodule NoIsNilGuardRemainingGuardFixture do
        def foo(x, y) when is_nil(x) and x == y, do: :ok
      end
      """

      expected = """
      defmodule NoIsNilGuardRemainingGuardFixture do
        def foo(nil = x, y) when x == y, do: :ok
      end
      """

      fixed = fix(NoIsNilGuard, code)
      confirm_fix(fixed, expected)
      assert {:ok, _diagnostics} = Credence.RuleHelpers.compile_and_capture(fixed)
    end
  end

  # ── param used in body ─────────────────────────────────────────

  describe "param used in body" do
    test "one-liner uses nil = param binding" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x) when is_nil(x), do: inspect(x)"),
        "def foo(nil = x), do: inspect(x)"
      )
    end

    test "combined guard with param used in body" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x, y) when is_nil(x) and is_binary(y), do: {x, y}"),
        "def foo(nil = x, y) when is_binary(y), do: {x, y}"
      )
    end

    test "only the used param gets nil = binding" do
      confirm_fix(
        fix(NoIsNilGuard, "def foo(x, y) when is_nil(x) and is_nil(y), do: inspect(x)"),
        "def foo(nil = x, nil), do: inspect(x)"
      )
    end
  end

  # ── block form ─────────────────────────────────────────────────

  describe "block form" do
    test "param unused" do
      code = """
      def foo(x) when is_nil(x) do
        :bar
      end
      """

      expected = """
      def foo(nil) do
        :bar
      end
      """

      confirm_fix(fix(NoIsNilGuard, code), expected)
    end

    test "param used in body" do
      code = """
      def foo(x) when is_nil(x) do
        inspect(x)
      end
      """

      expected = """
      def foo(nil = x) do
        inspect(x)
      end
      """

      confirm_fix(fix(NoIsNilGuard, code), expected)
    end
  end

  # ── realistic context ──────────────────────────────────────────

  describe "realistic context" do
    test "the actual pattern from the LLM log" do
      code =
        ~S'def palindrome?(string) when is_nil(string), do: raise ArgumentError, message: "cannot be nil"'

      expected = ~S'def palindrome?(nil), do: raise ArgumentError, message: "cannot be nil"'

      confirm_fix(fix(NoIsNilGuard, code), expected)
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def foo(x) when is_nil(x), do: :default
        def foo(x), do: x + 1
        def bar(y), do: y * 2
      end
      """

      expected = """
      defmodule Example do
        def foo(nil), do: :default
        def foo(x), do: x + 1
        def bar(y), do: y * 2
      end
      """

      confirm_fix(fix(NoIsNilGuard, code), expected)
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "already pattern matched nil" do
      code = "def foo(nil), do: :bar"

      confirm_fix(fix(NoIsNilGuard, code), code)
    end

    test "negated with not" do
      code = "def foo(x) when not is_nil(x), do: :ok"

      confirm_fix(fix(NoIsNilGuard, code), code)
    end

    test "or condition" do
      code = "def foo(x) when is_nil(x) or is_atom(x), do: :ok"

      confirm_fix(fix(NoIsNilGuard, code), code)
    end

    test "non-variable argument" do
      code = "def foo(x) when is_nil(hd(x)), do: :ok"

      confirm_fix(fix(NoIsNilGuard, code), code)
    end

    test "no is_nil at all" do
      code = "def foo(x) when is_binary(x), do: :ok"

      confirm_fix(fix(NoIsNilGuard, code), code)
    end
  end

  # ── round-trip ─────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(x) when is_nil(x), do: :default
        def b(x, y) when is_nil(x) and is_binary(y), do: y
        def c(x) when is_nil(x), do: inspect(x)
      end
      """

      assert check(NoIsNilGuard, fix(NoIsNilGuard, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(x) when is_nil(x), do: :default
        def b(x, y) when is_nil(y), do: x
        def c(x) when is_nil(x), do: inspect(x)
      end
      """

      assert valid_syntax?(fix(NoIsNilGuard, code))
    end
  end
end
