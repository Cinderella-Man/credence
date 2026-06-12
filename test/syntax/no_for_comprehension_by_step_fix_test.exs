defmodule Credence.Syntax.NoForComprehensionByStepFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.NoForComprehensionByStep

  defp analyze(code), do: NoForComprehensionByStep.analyze(code)
  defp fix(code), do: NoForComprehensionByStep.fix(code)

  test "fixes the syntax error" do
    input = """
    for multiple <- base..(limit - 1) by base do
      multiple
    end
    """

    expected = """
    for multiple <- Stream.iterate(base, &(&1 + base)) |> Stream.take_while(&(&1 <= (limit - 1))) do
      multiple
    end
    """

    assert fix(input) == expected
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             for multiple <- base..(limit - 1) by base do
               multiple
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             for multiple <- base..(limit - 1) by base do
               multiple
             end
             """)
           )
  end
end
