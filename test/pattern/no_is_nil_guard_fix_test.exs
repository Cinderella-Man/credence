defmodule Credence.Pattern.NoIsNilGuardFixTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoIsNilGuard.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoIsNilGuard.fix(code, [])
  end

  # ── sole guard, param unused ───────────────────────────────────

  describe "sole guard, param unused" do
    test "def one-liner" do
      assert fix("def foo(x) when is_nil(x), do: :bar") == "def foo(nil), do: :bar"
    end

    test "defp one-liner" do
      assert fix("defp foo(x) when is_nil(x), do: :bar") == "defp foo(nil), do: :bar"
    end

    test "multi-param, is_nil on first" do
      assert fix("def foo(x, y) when is_nil(x), do: y") == "def foo(nil, y), do: y"
    end

    test "multi-param, is_nil on second" do
      assert fix("def foo(x, y) when is_nil(y), do: x") == "def foo(x, nil), do: x"
    end

    test "three params, is_nil on middle" do
      assert fix("def foo(x, y, z) when is_nil(y), do: {x, z}") ==
               "def foo(x, nil, z), do: {x, z}"
    end
  end

  # ── combined guard with and ────────────────────────────────────

  describe "combined guard with and" do
    test "is_nil first, other guard kept" do
      assert fix("def foo(x, y) when is_nil(x) and is_binary(y), do: :ok") ==
               "def foo(nil, y) when is_binary(y), do: :ok"
    end

    test "is_nil second, other guard kept" do
      assert fix("def foo(x, y) when is_binary(y) and is_nil(x), do: :ok") ==
               "def foo(nil, y) when is_binary(y), do: :ok"
    end

    test "both params nil, guard dropped entirely" do
      assert fix("def foo(x, y) when is_nil(x) and is_nil(y), do: :ok") ==
               "def foo(nil, nil), do: :ok"
    end

    test "is_nil plus two other guards" do
      assert fix("def foo(x, y, z) when is_nil(x) and is_binary(y) and is_integer(z), do: :ok") ==
               "def foo(nil, y, z) when is_binary(y) and is_integer(z), do: :ok"
    end
  end

  # ── param used in body ─────────────────────────────────────────

  describe "param used in body" do
    test "one-liner uses nil = param binding" do
      assert fix("def foo(x) when is_nil(x), do: inspect(x)") ==
               "def foo(nil = x), do: inspect(x)"
    end

    test "combined guard with param used in body" do
      assert fix("def foo(x, y) when is_nil(x) and is_binary(y), do: {x, y}") ==
               "def foo(nil = x, y) when is_binary(y), do: {x, y}"
    end

    test "only the used param gets nil = binding" do
      assert fix("def foo(x, y) when is_nil(x) and is_nil(y), do: inspect(x)") ==
               "def foo(nil = x, nil), do: inspect(x)"
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

      assert fix(code) == expected
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

      assert fix(code) == expected
    end
  end

  # ── realistic context ──────────────────────────────────────────

  describe "realistic context" do
    test "the actual pattern from the LLM log" do
      code = """
      def palindrome?(string) when is_nil(string), do: raise ArgumentError, message: "cannot be nil"
      """

      fixed = fix(code)
      assert fixed =~ "def palindrome?(nil)"
      refute fixed =~ "when is_nil"
      refute fixed =~ "string"
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def foo(x) when is_nil(x), do: :default
        def foo(x), do: x + 1
        def bar(y), do: y * 2
      end
      """

      fixed = fix(code)
      assert fixed =~ "def foo(nil), do: :default"
      assert fixed =~ "def foo(x), do: x + 1"
      assert fixed =~ "def bar(y), do: y * 2"
      refute fixed =~ "is_nil"
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "already pattern matched nil" do
      code = "def foo(nil), do: :bar"
      assert fix(code) == code
    end

    test "negated with not" do
      code = "def foo(x) when not is_nil(x), do: :ok"
      assert fix(code) == code
    end

    test "or condition" do
      code = "def foo(x) when is_nil(x) or is_atom(x), do: :ok"
      assert fix(code) == code
    end

    test "non-variable argument" do
      code = "def foo(x) when is_nil(hd(x)), do: :ok"
      assert fix(code) == code
    end

    test "no is_nil at all" do
      code = "def foo(x) when is_binary(x), do: :ok"
      assert fix(code) == code
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

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(x) when is_nil(x), do: :default
        def b(x, y) when is_nil(y), do: x
        def c(x) when is_nil(x), do: inspect(x)
      end
      """

      assert {:ok, _} = Code.string_to_quoted(fix(code))
    end
  end
end
