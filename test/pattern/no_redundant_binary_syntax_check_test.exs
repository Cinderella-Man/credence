defmodule Credence.Pattern.NoRedundantBinarySyntaxCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoRedundantBinarySyntax

  # ── flags single string literal in binary syntax ───────────────

  describe "flags single string literal in binary syntax" do
    test "single char" do
      assert [%Issue{rule: :no_redundant_binary_syntax}] =
               check(NoRedundantBinarySyntax, ~S'<<"b">>')
    end

    test "multi-char" do
      assert [%Issue{}] =
               check(NoRedundantBinarySyntax, ~S'<<"hello">>')
    end

    test "empty string" do
      assert [%Issue{}] =
               check(NoRedundantBinarySyntax, ~S'<<"">>')
    end

    test "string with spaces" do
      assert [%Issue{}] =
               check(NoRedundantBinarySyntax, ~S'<<"hello world">>')
    end

    test "with spaces inside <<>>" do
      assert [%Issue{}] =
               check(NoRedundantBinarySyntax, ~S'<< "b" >>')
    end
  end

  # ── flags in various contexts ──────────────────────────────────

  describe "flags in various contexts" do
    test "inside a list" do
      assert [%Issue{}, %Issue{}, %Issue{}] =
               check(NoRedundantBinarySyntax, ~S'[<<"b">>, <<"a">>, <<"n">>]')
    end

    test "in assignment" do
      assert [%Issue{}] =
               check(NoRedundantBinarySyntax, ~S'x = <<"hello">>')
    end

    test "in function argument" do
      assert [%Issue{}] =
               check(NoRedundantBinarySyntax, ~S'String.length(<<"hello">>)')
    end

    test "in comparison" do
      assert [%Issue{}] =
               check(NoRedundantBinarySyntax, ~S'x == <<"hello">>')
    end

    test "in case expression" do
      code = """
      case x do
        <<"a">> -> :ok
        _ -> :error
      end
      """

      assert [%Issue{}] = check(NoRedundantBinarySyntax, code)
    end
  end

  # ── flags multiple violations ──────────────────────────────────

  describe "flags multiple violations" do
    test "multiple in one module" do
      code = """
      defmodule E do
        def f, do: <<"a">>
        def g, do: <<"b">>
      end
      """

      assert length(check(NoRedundantBinarySyntax, code)) == 2
    end
  end

  # ── does NOT flag ──────────────────────────────────────────────

  describe "does NOT flag" do
    test "bare string without <<>>" do
      assert check(NoRedundantBinarySyntax, ~S'"hello"') == []
    end

    test "byte values" do
      assert check(NoRedundantBinarySyntax, "<<1, 2, 3>>") == []
    end

    test "multiple string segments" do
      assert check(NoRedundantBinarySyntax, ~S'<<"a", "b">>') == []
    end

    test "pattern with rest" do
      assert check(NoRedundantBinarySyntax, ~S'<<"a", rest::binary>>') == []
    end

    test "variable with type specifier" do
      assert check(NoRedundantBinarySyntax, "<<x::utf8>>") == []
    end

    test "bare variable" do
      assert check(NoRedundantBinarySyntax, "<<x>>") == []
    end

    test "integer literal" do
      assert check(NoRedundantBinarySyntax, "<<255>>") == []
    end

    test "string with type specifier" do
      assert check(NoRedundantBinarySyntax, ~S'<<"a"::binary>>') == []
    end

    test "mixed string and integer" do
      assert check(NoRedundantBinarySyntax, ~S'<<"a", 0>>') == []
    end
  end

  # ── does NOT flag sigils (regression) ──────────────────────────

  describe "does NOT flag sigils (regression)" do
    test "regex sigil ~r" do
      assert check(NoRedundantBinarySyntax, "~r/[^a-z0-9]/") == []
    end

    test "regex sigil with modifier" do
      assert check(NoRedundantBinarySyntax, "~r/\\W+/u") == []
    end

    test "word sigil ~w" do
      assert check(NoRedundantBinarySyntax, "~w(alpha beta gamma)") == []
    end

    test "string sigil ~s" do
      assert check(NoRedundantBinarySyntax, "~s(hello world)") == []
    end

    test "uppercase (raw) string sigil ~S" do
      assert check(NoRedundantBinarySyntax, "~S(hello world)") == []
    end

    test "regex inside a pipe" do
      code = """
      defmodule E do
        def clean(text), do: String.replace(text, ~r/[^a-z0-9]/, "")
      end
      """

      assert check(NoRedundantBinarySyntax, code) == []
    end

    test "module attribute with word sigil" do
      code = """
      defmodule E do
        @vowels ~w(a e i o u)
        def vowels, do: @vowels
      end
      """

      assert check(NoRedundantBinarySyntax, code) == []
    end
  end

  # ── metadata ───────────────────────────────────────────────────

  describe "metadata" do
    test "meta.line is set" do
      [issue] =
        check(NoRedundantBinarySyntax, ~S'<<"hello">>')

      assert issue.meta.line != nil
    end
  end
end
