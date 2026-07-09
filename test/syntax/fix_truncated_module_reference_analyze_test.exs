defmodule Credence.Syntax.FixTruncatedModuleReferenceAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixTruncatedModuleReference

  defp analyze(code), do: FixTruncatedModuleReference.analyze(code)

  describe "flags truncated __MODULE__ reference" do
    test "in GenServer.start_link call" do
      assert [%Issue{rule: :fix_truncated_module_reference}] =
               analyze("GenServer.start_link(__MODULE%, %{key: :val}, name: __MODULE__)")
    end

    test "standalone truncated reference" do
      assert [%Issue{rule: :fix_truncated_module_reference}] =
               analyze("__MODULE%")
    end

    test "in map value" do
      assert [%Issue{rule: :fix_truncated_module_reference}] =
               analyze("%{key: __MODULE%}")
    end

    test "multiple occurrences on different lines" do
      assert [%Issue{}, %Issue{}] =
               analyze("""
               x = __MODULE%
               y = __MODULE%
               """)
    end
  end

  describe "leaves good code alone" do
    test "correct __MODULE__ reference" do
      assert analyze("GenServer.start_link(__MODULE__, %{key: :val}, name: __MODULE__)") == []
    end

    test "plain code without __MODULE" do
      assert analyze("foo(bar)") == []
    end

    test "__MODULE__ in module attribute" do
      assert analyze("@module __MODULE__") == []
    end
  end
end
