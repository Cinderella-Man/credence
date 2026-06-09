defmodule Credence.Syntax.NoOrphanedModuleAttributesFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoOrphanedModuleAttributes

  defp analyze(code), do: NoOrphanedModuleAttributes.analyze(code)
  defp fix(code), do: NoOrphanedModuleAttributes.fix(code)

  test "fixes the syntax error" do
    input = """
    @spec foo(x :: integer()) :: integer()
    def foo(x), do: x + 1
    """

    expected = """
    defmodule Solution do
      @spec foo(x :: integer()) :: integer()
      def foo(x), do: x + 1
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             @spec foo() :: :ok
             def foo, do: :ok
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             @spec foo() :: :ok
             def foo, do: :ok
             """)
           )
  end
end