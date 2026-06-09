defmodule Credence.Syntax.NoOrphanedModuleAttributesAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.NoOrphanedModuleAttributes

  defp analyze(code), do: NoOrphanedModuleAttributes.analyze(code)

  test "flags the unparseable code" do
    assert [%Issue{rule: :no_orphaned_module_attributes}] =
             analyze("""
             @spec foo() :: :ok
             def foo, do: :ok
             """)
  end

  test "leaves good code alone" do
    assert analyze("""
           defmodule Solution do
             @spec foo() :: :ok
             def foo, do: :ok
           end
           """) == []
  end
end