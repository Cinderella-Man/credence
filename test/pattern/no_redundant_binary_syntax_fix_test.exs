defmodule Credence.Pattern.NoRedundantBinarySyntaxFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantBinarySyntax

  # ── single string literal ─────────────────────────────────────

  describe "single string literal" do
    test "single char" do
      assert fix(NoRedundantBinarySyntax, ~s(<<"b">>)) == ~s("b")
    end

    test "multi-char" do
      assert fix(NoRedundantBinarySyntax, ~s(<<"hello">>)) == ~s("hello")
    end

    test "empty string" do
      assert fix(NoRedundantBinarySyntax, ~s(<<"">>)) == ~s("")
    end

    test "string with spaces" do
      assert fix(NoRedundantBinarySyntax, ~s(<<"hello world">>)) == ~s("hello world")
    end

    test "with spaces inside <<>>" do
      assert fix(NoRedundantBinarySyntax, ~s(<< "b" >>)) == ~s("b")
    end
  end

  # ── multiple on same line ──────────────────────────────────────

  describe "multiple on same line" do
    test "list of wrapped graphemes" do
      assert fix(NoRedundantBinarySyntax, ~s([<<"b">>, <<"a">>, <<"n">>])) == ~s(["b", "a", "n"])
    end

    test "tuple of wrapped strings" do
      assert fix(NoRedundantBinarySyntax, ~s({<<"x">>, <<"y">>})) == ~s({"x", "y"})
    end
  end

  # ── realistic context ──────────────────────────────────────────

  describe "realistic context" do
    test "fixes binary syntax inside assert" do
      code = ~s{assert Mod.func("banana") == [<<"b">>, <<"a">>, <<"n">>]}
      fixed = fix(NoRedundantBinarySyntax, code)
      assert fixed == ~s{assert Mod.func("banana") == ["b", "a", "n"]}
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar, do: [<<"a">>, <<"b">>]
        def baz(y), do: y * 2
      end
      """

      expected = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar, do: ["a", "b"]
        def baz(y), do: y * 2
      end
      """

      assert fix(NoRedundantBinarySyntax, code) == expected
    end

    test "fixes in case expression" do
      code = """
      case x do
        <<"a">> -> :ok
        _ -> :error
      end
      """

      expected = """
      case x do
        "a" -> :ok
        _ -> :error
      end
      """

      assert fix(NoRedundantBinarySyntax, code) == expected
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "returns source unchanged when nothing to fix" do
      code = ~s(x = "hello")
      assert fix(NoRedundantBinarySyntax, code) == code
    end

    test "does not touch byte values" do
      code = "<<1, 2, 3>>"
      assert fix(NoRedundantBinarySyntax, code) == code
    end

    test "does not touch multiple string segments" do
      code = ~s(<<"a", "b">>)
      assert fix(NoRedundantBinarySyntax, code) == code
    end

    test "does not touch pattern with rest" do
      code = ~s(<<"a", rest::binary>>)
      assert fix(NoRedundantBinarySyntax, code) == code
    end

    test "does not touch variable with type specifier" do
      code = "<<x::utf8>>"
      assert fix(NoRedundantBinarySyntax, code) == code
    end

    test "does not touch string with type specifier" do
      code = ~s(<<"a"::binary>>)
      assert fix(NoRedundantBinarySyntax, code) == code
    end

    test "does not touch regex sigils" do
      code = ~s{String.replace(text, ~r/[^a-z0-9]/, "")}
      assert fix(NoRedundantBinarySyntax, code) == code
    end

    test "does not touch word sigils" do
      code = "@vowels ~w(a e i o u)"
      assert fix(NoRedundantBinarySyntax, code) == code
    end
  end

  # ── round-trip ─────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a, do: <<"hello">>
        def b, do: [<<"a">>, <<"b">>, <<"c">>]
        def c, do: {<<"x">>, <<"y">>}
      end
      """

      assert check(NoRedundantBinarySyntax, fix(NoRedundantBinarySyntax, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a, do: <<"hello">>
        def b, do: [<<"a">>, <<"b">>]
        def c(x), do: x == <<"test">>
      end
      """

      assert valid_syntax?(fix(NoRedundantBinarySyntax, code))
    end
  end
end
