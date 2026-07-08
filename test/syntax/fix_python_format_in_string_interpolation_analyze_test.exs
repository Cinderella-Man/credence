defmodule Credence.Syntax.FixPythonFormatInStringInterpolationAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixPythonFormatInStringInterpolation

  defp analyze(code), do: FixPythonFormatInStringInterpolation.analyze(code)

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — Python-style format specifier in interpolation
  # ═══════════════════════════════════════════════════════════════════

  describe "flags Python-style format specifier" do
    test "cents_part:02" do
      assert [%Issue{rule: :fix_python_format_in_string_interpolation}] =
               analyze(~S'"#{cents_part:02}"')
    end

    test "n:05" do
      assert [%Issue{}] =
               analyze(~S'"#{n:05}"')
    end

    test "x:01" do
      assert [%Issue{}] =
               analyze(~S'"#{x:01}"')
    end

    test "val:010" do
      assert [%Issue{}] =
               analyze(~S'"#{val:010}"')
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — inside a module definition
  # ═══════════════════════════════════════════════════════════════════

  describe "flags inside module definition" do
    test "full module with format specifier" do
      code = """
      defmodule FormatFix do
        def format_price(cents) do
          dollars = div(cents, 100)
          cents_part = rem(cents, 100)
          "\#{dollars}.\#{cents_part:02}"
        end
      end
      """

      assert [%Issue{}] = analyze(code)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — multiple on same line
  # ═══════════════════════════════════════════════════════════════════

  describe "flags multiple on same line" do
    test "two format specifiers" do
      assert [%Issue{}] =
               analyze(~S'"#{a:02}-#{b:03}"')
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FLAGS — multiple lines
  # ═══════════════════════════════════════════════════════════════════

  describe "flags multiple lines" do
    test "each line gets its own issue" do
      code = """
      "\#{a:02}"
      "\#{b:03}"
      """

      assert length(analyze(code)) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — plain interpolation
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag plain interpolation" do
    test "variable only" do
      assert analyze(~S'"#{variable}"') == []
    end

    test "function call" do
      assert analyze(~S'"#{inspect(map)}"') == []
    end

    test "two plain interpolations" do
      assert analyze(~S'"#{dollars}.#{cents_part}"') == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — map/keyword syntax
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag map/keyword syntax" do
    test "map literal" do
      assert analyze("%{key: value}") == []
    end

    test "keyword list" do
      assert analyze("foo(key: value)") == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DOES NOT FLAG — already correct Elixir
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag already correct Elixir" do
    test "String.pad_leading usage" do
      assert analyze(~S'"#{String.pad_leading(Integer.to_string(x), 2, "0")}"') == []
    end

    test "no interpolation at all" do
      assert analyze("hello world") == []
    end

    test "empty string" do
      assert analyze(~S'""') == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # METADATA
  # ═══════════════════════════════════════════════════════════════════

  describe "metadata" do
    test "reports correct line number" do
      code = """
      x = 1
      "\#{cents_part:02}"
      y = 3
      """

      [issue] = analyze(code)
      assert issue.meta.line == 2
    end
  end
end
