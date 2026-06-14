defmodule Credence.Syntax.PreferScanOverScanlFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferScanOverScanl

  defp analyze(code), do: PreferScanOverScanl.analyze(code)
  defp fix(code), do: PreferScanOverScanl.fix(code)

  test "fixes Enum.scanl to Enum.scan" do
    input = """
    defmodule Solution do
      def prefix_sums(list) do
        Enum.scanl(list, 0, &+/2)
      end
    end
    """

    expected = """
    defmodule Solution do
      def prefix_sums(list) do
        Enum.scan(list, 0, &+/2)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               def prefix_sums(list) do
                 Enum.scanl(list, 0, &+/2)
               end
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               def prefix_sums(list) do
                 Enum.scanl(list, 0, &+/2)
               end
             end
             """)
           )
  end

  test "fix is idempotent on already-correct code" do
    code = """
    defmodule Solution do
      def prefix_sums(list) do
        Enum.scan(list, 0, &+/2)
      end
    end
    """

    confirm_fix(fix(code), code)
  end
end
