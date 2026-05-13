defmodule Credence.Syntax.FixStaleAccessModifierAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue

  defp analyze(code), do: Credence.Syntax.FixStaleAccessModifier.analyze(code)

  # ── flags prefixed defs ────────────────────────────────────────

  describe "flags garbled prefixes" do
    test "pprivate defp" do
      assert [%Issue{rule: :stale_access_modifier}] =
               analyze("pprivate defp calculate(x) do\n  x * 2\nend")
    end
  end

  describe "flags redundant prefixes" do
    test "private defp" do
      assert [%Issue{}] = analyze("private defp calculate(x) do\n  x * 2\nend")
    end

    test "public def" do
      assert [%Issue{}] = analyze("public def calculate(x) do\n  x * 2\nend")
    end
  end

  describe "flags contradictory prefixes" do
    test "private def (trusts the Elixir keyword)" do
      assert [%Issue{}] = analyze("private def calculate(x) do\n  x * 2\nend")
    end

    test "public defp" do
      assert [%Issue{}] = analyze("public defp calculate(x) do\n  x * 2\nend")
    end
  end

  describe "flags other language modifiers" do
    test "static def" do
      assert [%Issue{}] = analyze("static def calculate(x), do: x * 2")
    end

    test "static defp" do
      assert [%Issue{}] = analyze("static defp calculate(x), do: x * 2")
    end

    test "protected defp" do
      assert [%Issue{}] = analyze("protected defp calculate(x), do: x * 2")
    end

    test "abstract def" do
      assert [%Issue{}] = analyze("abstract def calculate(x)")
    end

    test "async def" do
      assert [%Issue{}] = analyze("async def fetch(url), do: url")
    end

    test "pub def" do
      assert [%Issue{}] = analyze("pub def calculate(x), do: x * 2")
    end

    test "export def" do
      assert [%Issue{}] = analyze("export def calculate(x), do: x * 2")
    end

    test "final def" do
      assert [%Issue{}] = analyze("final def calculate(x), do: x * 2")
    end
  end

  describe "flags macro definitions too" do
    test "private defmacro" do
      assert [%Issue{}] = analyze("private defmacro my_macro(x) do\n  x\nend")
    end

    test "private defmacrop" do
      assert [%Issue{}] = analyze("private defmacrop my_macro(x) do\n  x\nend")
    end
  end

  describe "flags with indentation" do
    test "indented pprivate defp" do
      assert [%Issue{}] = analyze("  pprivate defp calculate(x), do: x * 2")
    end

    test "deeply indented" do
      assert [%Issue{}] = analyze("      private defp calculate(x), do: x * 2")
    end
  end

  describe "flags multiple in same source" do
    test "two prefixed defs" do
      code = """
      private defp foo(x), do: x
      public def bar(y), do: y
      """

      assert length(analyze(code)) == 2
    end
  end

  # ── does NOT flag ──────────────────────────────────────────────

  describe "does NOT flag" do
    test "plain def" do
      assert analyze("def calculate(x) do\n  x * 2\nend") == []
    end

    test "plain defp" do
      assert analyze("defp calculate(x) do\n  x * 2\nend") == []
    end

    test "plain defmacro" do
      assert analyze("defmacro my_macro(x) do\n  x\nend") == []
    end

    test "private as variable name" do
      assert analyze("private = true") == []
    end

    test "word private not followed by def keyword" do
      assert analyze("private_function(x)") == []
    end

    test "no code at all" do
      assert analyze("x = 1 + 2") == []
    end
  end

  # ── metadata ───────────────────────────────────────────────────

  describe "metadata" do
    test "reports correct line number" do
      code = "def foo, do: :ok\nprivate defp bar(x), do: x\ndef baz, do: :ok"
      [issue] = analyze(code)
      assert issue.meta.line == 2
    end
  end
end
