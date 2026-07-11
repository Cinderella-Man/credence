defmodule Credence.Syntax.FixIfInlineElseCaseBlockFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixIfInlineElseCaseBlock

  defp analyze(code), do: FixIfInlineElseCaseBlock.analyze(code)
  defp fix(code), do: FixIfInlineElseCaseBlock.fix(code)

  test "fixes the syntax error" do
    input = """
    if weight > 0, do: true, else:
      case x do
        nil -> false
        _ -> true
      end
    """

    expected = """
    if weight > 0 do
      true
    else
      case x do
        nil -> false
        _ -> true
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = """
    if weight > 0, do: true, else:
      case x do
        nil -> false
        _ -> true
      end
    """

    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = """
    if weight > 0, do: true, else:
      case x do
        nil -> false
        _ -> true
      end
    """

    assert valid_syntax?(fix(code))
  end
end
