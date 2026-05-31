defmodule Credence.Syntax.FixModuleAttrOutsideModuleAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixModuleAttrOutsideModule

  defp analyze(code) do
    FixModuleAttrOutsideModule.analyze(code)
  end

  # ── flags module attrs outside defmodule ─────────────────────────

  describe "flags module attributes before defmodule" do
    test "@moduledoc before defmodule" do
      code = "@moduledoc \"some doc\"\ndefmodule Foo do\nend\n"
      assert [%Issue{rule: :module_attr_outside_module}] = analyze(code)
    end

    test "@doc before defmodule" do
      code = "@doc \"some doc\"\ndefmodule Foo do\nend\n"
      assert [%Issue{}] = analyze(code)
    end

    test "@spec before defmodule" do
      code = "@spec foo() :: :ok\ndefmodule Foo do\nend\n"
      assert [%Issue{}] = analyze(code)
    end

    test "@type before defmodule" do
      code = "@type t :: atom()\ndefmodule Foo do\nend\n"
      assert [%Issue{}] = analyze(code)
    end

    test "multiple attrs before defmodule" do
      code = "@moduledoc \"doc\"\n@doc \"fn doc\"\n@spec foo() :: :ok\ndefmodule Foo do\nend\n"
      assert [%Issue{}] = analyze(code)
    end

    test "@moduledoc with heredoc before defmodule" do
      code = "@moduledoc \"\"\"\nSome module doc\n\"\"\"\ndefmodule Foo do\nend\n"
      assert [%Issue{}] = analyze(code)
    end

    test "@impl before defmodule" do
      code = "@impl true\ndefmodule Foo do\nend\n"
      assert [%Issue{}] = analyze(code)
    end
  end

  # ── does NOT flag ───────────────────────────────────────────────

  describe "does NOT flag" do
    test "attrs inside defmodule" do
      code = "defmodule Foo do\n  @moduledoc \"doc\"\nend\n"
      assert analyze(code) == []
    end

    test "no module attributes at all" do
      code = "defmodule Foo do\n  def bar, do: :ok\nend\n"
      assert analyze(code) == []
    end

    test "no defmodule but has attrs" do
      code = "@moduledoc \"doc\"\ndef foo, do: :ok\n"
      assert [%Issue{}] = analyze(code)
    end

    test "module attribute after defmodule (inside)" do
      code = "defmodule Foo do\n  @moduledoc \"doc\"\n  def bar, do: :ok\nend\n"
      assert analyze(code) == []
    end
  end
end
