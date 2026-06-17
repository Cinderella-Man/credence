defmodule Credence.Pattern.NoRedundantBinarySyntaxFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantBinarySyntax

  # ── single string literal ─────────────────────────────────────

  describe "single string literal" do
    test "single char" do
      confirm_fix(fix(NoRedundantBinarySyntax, ~S'<<"b">>'), ~S'"b"')
    end

    test "multi-char" do
      confirm_fix(fix(NoRedundantBinarySyntax, ~S'<<"hello">>'), ~S'"hello"')
    end

    test "empty string" do
      confirm_fix(fix(NoRedundantBinarySyntax, ~S'<<"">>'), ~S'""')
    end

    test "string with spaces" do
      confirm_fix(fix(NoRedundantBinarySyntax, ~S'<<"hello world">>'), ~S'"hello world"')
    end

    test "with spaces inside <<>>" do
      confirm_fix(fix(NoRedundantBinarySyntax, ~S'<< "b" >>'), ~S'"b"')
    end
  end

  # ── multiple on same line ──────────────────────────────────────

  describe "multiple on same line" do
    test "list of wrapped graphemes" do
      confirm_fix(
        fix(NoRedundantBinarySyntax, ~S'[<<"b">>, <<"a">>, <<"n">>]'),
        ~S'["b", "a", "n"]'
      )
    end

    test "tuple of wrapped strings" do
      confirm_fix(fix(NoRedundantBinarySyntax, ~S'{<<"x">>, <<"y">>}'), ~S'{"x", "y"}')
    end
  end

  # ── realistic context ──────────────────────────────────────────

  describe "realistic context" do
    test "fixes binary syntax inside assert" do
      code = ~S'assert Mod.func("banana") == [<<"b">>, <<"a">>, <<"n">>]'
      fixed = fix(NoRedundantBinarySyntax, code)
      confirm_fix(fixed, ~S'assert Mod.func("banana") == ["b", "a", "n"]')
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

      confirm_fix(fix(NoRedundantBinarySyntax, code), expected)
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

      confirm_fix(fix(NoRedundantBinarySyntax, code), expected)
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "parallel binary clause" do
    test "keeps a <<literal>> head that lines up with a binary-match clause" do
      code = """
      case url do
        <<"/">> -> root()
        <<"/", rest::binary>> -> sub(rest)
        _ -> other()
      end
      """

      confirm_fix(fix(NoRedundantBinarySyntax, code), code)
    end

    test "still fixes a <<literal>> in a clause body" do
      code = """
      case url do
        <<"/", rest::binary>> -> handle(<<"x">>, rest)
        <<"/">> -> root()
      end
      """

      expected = """
      case url do
        <<"/", rest::binary>> -> handle("x", rest)
        <<"/">> -> root()
      end
      """

      confirm_fix(fix(NoRedundantBinarySyntax, code), expected)
    end
  end

  describe "no-ops" do
    test "returns source unchanged when nothing to fix" do
      code = ~S'x = "hello"'
      confirm_fix(fix(NoRedundantBinarySyntax, code), code)
    end

    test "does not touch byte values" do
      code = "<<1, 2, 3>>"
      confirm_fix(fix(NoRedundantBinarySyntax, code), code)
    end

    test "does not touch multiple string segments" do
      code = ~S'<<"a", "b">>'
      confirm_fix(fix(NoRedundantBinarySyntax, code), code)
    end

    test "does not touch pattern with rest" do
      code = ~S'<<"a", rest::binary>>'
      confirm_fix(fix(NoRedundantBinarySyntax, code), code)
    end

    test "does not touch variable with type specifier" do
      code = "<<x::utf8>>"
      confirm_fix(fix(NoRedundantBinarySyntax, code), code)
    end

    test "does not touch string with type specifier" do
      code = ~S'<<"a"::binary>>'
      confirm_fix(fix(NoRedundantBinarySyntax, code), code)
    end

    test "does not touch regex sigils" do
      code = ~S'String.replace(text, ~r/[^a-z0-9]/, "")'
      confirm_fix(fix(NoRedundantBinarySyntax, code), code)
    end

    test "does not touch word sigils" do
      code = "@vowels ~w(a e i o u)"
      confirm_fix(fix(NoRedundantBinarySyntax, code), code)
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
