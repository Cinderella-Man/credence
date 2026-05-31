defmodule Credence.Syntax.FixModuleAttrOutsideModuleFixTest do
  use ExUnit.Case

  alias Credence.Syntax.FixModuleAttrOutsideModule

  defp fix(code) do
    FixModuleAttrOutsideModule.fix(code)
  end

  defp analyze(code) do
    FixModuleAttrOutsideModule.analyze(code)
  end

  # ── simple cases ────────────────────────────────────────────────

  describe "single attribute" do
    test "moves @moduledoc inside defmodule" do
      code = "@moduledoc \"some doc\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      expected = "defmodule Foo do\n  @moduledoc \"some doc\"\n  def bar, do: :ok\nend\n"
      assert fix(code) == expected
    end

    test "moves @spec inside defmodule" do
      code = "@spec foo() :: :ok\ndefmodule Foo do\n  def foo, do: :ok\nend\n"
      expected = "defmodule Foo do\n  @spec foo() :: :ok\n  def foo, do: :ok\nend\n"
      assert fix(code) == expected
    end
  end

  # ── heredoc attributes ─────────────────────────────────────────

  describe "heredoc attributes" do
    test "moves @moduledoc with heredoc inside defmodule" do
      code = "@moduledoc \"\"\"\nSome doc\n\"\"\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      expected = "defmodule Foo do\n  @moduledoc \"\"\"\n  Some doc\n  \"\"\"\n  def bar, do: :ok\nend\n"
      assert fix(code) == expected
    end

    test "the actual LLM pattern from the log" do
      code = "@moduledoc \"\"\"\nConverts sentences.\n\"\"\"\n@doc \"\"\"\nConverts a sentence.\n\"\"\"\n@spec foo(String.t()) :: integer()\ndefmodule Solution do\n  def foo(s), do: 0\nend\n"
      result = fix(code)

      # All attrs should be inside the module
      assert result =~ "defmodule Solution do\n  @moduledoc"
      assert result =~ "  @moduledoc \"\"\"\n  Converts sentences.\n  \"\"\""
      assert result =~ "  @doc \"\"\"\n  Converts a sentence.\n  \"\"\""
      assert result =~ "  @spec foo(String.t()) :: integer()"
    end
  end

  # ── multiple attributes ────────────────────────────────────────

  describe "multiple attributes" do
    test "moves all attrs inside defmodule" do
      code = "@moduledoc \"mod doc\"\n@doc \"fn doc\"\n@spec foo() :: :ok\ndefmodule Foo do\n  def foo, do: :ok\nend\n"
      result = fix(code)

      assert result =~ "defmodule Foo do\n  @moduledoc"
      assert result =~ "  @doc \"fn doc\""
      assert result =~ "  @spec foo() :: :ok"
    end

    test "blank lines between attrs are preserved" do
      code = "@moduledoc \"\"\"\nMod doc\n\"\"\"\n\n@doc \"\"\"\nFn doc\n\"\"\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      result = fix(code)

      # Should have blank line between @moduledoc block and @doc block
      assert result =~ "\"\"\"\n\n  @doc"
    end
  end

  # ── indentation ────────────────────────────────────────────────

  describe "indentation" do
    test "matches body indentation" do
      code = "@spec foo() :: :ok\ndefmodule Foo do\n    def foo, do: :ok\nend\n"
      result = fix(code)
      assert result =~ "    @spec foo() :: :ok"
    end

    test "defaults to 2 spaces when body is empty" do
      code = "@spec foo() :: :ok\ndefmodule Foo do\nend\n"
      result = fix(code)
      assert result =~ "  @spec foo() :: :ok"
    end
  end

  # ── non-attr code before defmodule ─────────────────────────────

  describe "non-attr code before defmodule" do
    test "only moves trailing attrs, keeps other code" do
      code = "IO.puts(\"hello\")\n@moduledoc \"doc\"\ndefmodule Foo do\n  def bar, do: :ok\nend\n"
      result = fix(code)

      assert result =~ "IO.puts(\"hello\")\ndefmodule Foo do\n  @moduledoc \"doc\""
    end
  end

  # ── trailing blank lines ───────────────────────────────────────

  describe "trailing blank lines" do
    test "blank line between last attr and defmodule is removed" do
      code = "@spec foo() :: :ok\n\ndefmodule Foo do\n  def foo, do: :ok\nend\n"
      result = fix(code)

      # The blank line before defmodule should not be preserved
      assert result =~ "@spec foo() :: :ok\n  def foo"
    end
  end

  # ── bare code without defmodule ────────────────────────────────

  describe "bare code without defmodule" do
    test "wraps @doc + @spec + def in defmodule Solution" do
      code = "@doc \"some doc\"\n@spec foo() :: :ok\ndef foo, do: :ok\n"
      result = fix(code)
      assert result =~ "defmodule Solution do\n  @doc"
      assert result =~ "  @spec foo() :: :ok"
      assert result =~ "  def foo, do: :ok\nend\n"
    end

    test "wraps heredoc @doc with def in defmodule Solution" do
      code = "@doc \"\"\"\nGiven a non-negative integer n.\n\"\"\"\n@spec foo(non_neg_integer()) :: non_neg_integer()\ndef foo(0), do: 1\ndef foo(n), do: n\n"
      result = fix(code)
      assert result =~ "defmodule Solution do\n  @doc \"\"\""
      assert result =~ "  Given a non-negative integer n.\n  \"\"\""
      assert result =~ "  @spec foo(non_neg_integer()) :: non_neg_integer()"
      assert result =~ "  def foo(0), do: 1"
    end

    test "does not wrap code with no module attributes" do
      code = "def foo, do: :ok\n"
      assert fix(code) == code
    end

    test "round-trip: fixed bare code produces zero analyze issues" do
      code = ~s(@doc "some doc"\ndef foo, do: :ok\n)
      assert analyze(fix(code)) == []
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "attrs already inside defmodule" do
      code = "defmodule Foo do\n  @moduledoc \"doc\"\n  def bar, do: :ok\nend\n"
      assert fix(code) == code
    end

    test "no defmodule wraps in defmodule Solution" do
      code = "@moduledoc \"doc\"\ndef foo, do: :ok\n"
      result = fix(code)
      assert result =~ "defmodule Solution do\n  @moduledoc"
      assert result =~ "  def foo, do: :ok\nend\n"
    end

    test "no module attributes" do
      code = "defmodule Foo do\n  def bar, do: :ok\nend\n"
      assert fix(code) == code
    end
  end

  # ── round-trip ─────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed code produces zero analyze issues" do
      code = "@moduledoc \"\"\"\nSome doc\n\"\"\"\n@spec foo() :: :ok\ndefmodule Foo do\n  def foo, do: :ok\nend\n"
      assert analyze(fix(code)) == []
    end
  end
end
