defmodule Credence.Pattern.NoRedundantBinarySyntaxFixTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoRedundantBinarySyntax.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(Credence.Pattern.NoRedundantBinarySyntax, code, [])
  end

  # ── single string literal ─────────────────────────────────────

  describe "single string literal" do
    test "single char" do
      assert fix("<<\"b\">>") == "\"b\""
    end

    test "multi-char" do
      assert fix("<<\"hello\">>") == "\"hello\""
    end

    test "empty string" do
      assert fix("<<\"\">>") == "\"\""
    end

    test "string with spaces" do
      assert fix("<<\"hello world\">>") == "\"hello world\""
    end

    test "with spaces inside <<>>" do
      assert fix("<< \"b\" >>") == "\"b\""
    end
  end

  # ── multiple on same line ──────────────────────────────────────

  describe "multiple on same line" do
    test "list of wrapped graphemes" do
      assert fix("[<<\"b\">>, <<\"a\">>, <<\"n\">>]") == "[\"b\", \"a\", \"n\"]"
    end

    test "tuple of wrapped strings" do
      assert fix("{<<\"x\">>, <<\"y\">>}") == "{\"x\", \"y\"}"
    end
  end

  # ── realistic context ──────────────────────────────────────────

  describe "realistic context" do
    test "fixes binary syntax inside assert" do
      code = "assert Mod.func(\"banana\") == [<<\"b\">>, <<\"a\">>, <<\"n\">>]"
      fixed = fix(code)
      assert fixed == "assert Mod.func(\"banana\") == [\"b\", \"a\", \"n\"]"
    end

    test "preserves surrounding code" do
      code = """
      defmodule Example do
        def foo(x), do: x + 1
        def bar, do: [<<"a">>, <<"b">>]
        def baz(y), do: y * 2
      end
      """

      fixed = fix(code)
      assert fixed =~ "def foo(x), do: x + 1"
      assert fixed =~ "[\"a\", \"b\"]"
      assert fixed =~ "def baz(y), do: y * 2"
      refute fixed =~ "<<"
    end

    test "fixes in case expression" do
      code = """
      case x do
        <<"a">> -> :ok
        _ -> :error
      end
      """

      fixed = fix(code)
      assert fixed =~ "\"a\" -> :ok"
      refute fixed =~ "<<"
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "returns source unchanged when nothing to fix" do
      code = "x = \"hello\""
      assert fix(code) == code
    end

    test "does not touch byte values" do
      code = "<<1, 2, 3>>"
      assert fix(code) == code
    end

    test "does not touch multiple string segments" do
      code = "<<\"a\", \"b\">>"
      assert fix(code) == code
    end

    test "does not touch pattern with rest" do
      code = "<<\"a\", rest::binary>>"
      assert fix(code) == code
    end

    test "does not touch variable with type specifier" do
      code = "<<x::utf8>>"
      assert fix(code) == code
    end

    test "does not touch string with type specifier" do
      code = "<<\"a\"::binary>>"
      assert fix(code) == code
    end

    test "does not touch regex sigils" do
      code = "String.replace(text, ~r/[^a-z0-9]/, \"\")"
      assert fix(code) == code
    end

    test "does not touch word sigils" do
      code = "@vowels ~w(a e i o u)"
      assert fix(code) == code
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

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a, do: <<"hello">>
        def b, do: [<<"a">>, <<"b">>]
        def c(x), do: x == <<"test">>
      end
      """

      assert {:ok, _} = Code.string_to_quoted(fix(code))
    end
  end
end
