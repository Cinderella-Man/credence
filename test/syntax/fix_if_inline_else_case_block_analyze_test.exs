defmodule Credence.Syntax.FixIfInlineElseCaseBlockAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixIfInlineElseCaseBlock

  defp analyze(code), do: FixIfInlineElseCaseBlock.analyze(code)

  test "flags the unparseable code" do
    code = """
    if weight > 0, do: true, else:
      case x do
        nil -> false
        _ -> true
      end
    """

    assert [%Issue{rule: :fix_if_inline_else_case_block}] = analyze(code)
  end

  test "leaves good code alone" do
    code = """
    if weight > 0 do
      true
    else
      case x do
        nil -> false
        _ -> true
      end
    end
    """

    assert analyze(code) == []
  end
end
