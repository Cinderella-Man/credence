defmodule Credence.Syntax.NoElseInForComprehensionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoElseInForComprehension

  defp analyze(code), do: NoElseInForComprehension.analyze(code)
  defp fix(code), do: NoElseInForComprehension.fix(code)

  test "fixes the syntax error" do
    input = """
    for x <- [1, 2, 3] do
      x * 2
    else
      _ -> []
    end
    """

    expected = """
    for x <- [1, 2, 3] do
      x * 2
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("""
           for x <- [1, 2, 3] do
             x * 2
           else
             _ -> []
           end
           """)) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("""
           for x <- [1, 2, 3] do
             x * 2
           else
             _ -> []
           end
           """))
  end

  test "preserves inner if/else that is not the for else" do
    input = """
    for <<c <- "hello">> do
      if c >= ?0 and c <= ?9 do
        "*"
      else
        <<c>>
      end
    else
      _ -> []
    end
    """

    expected = """
    for <<c <- "hello">> do
      if c >= ?0 and c <= ?9 do
        "*"
      else
        <<c>>
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "preserves inner if/else that is not the for else (parses)" do
    assert valid_syntax?(fix("""
           for <<c <- "hello">> do
             if c >= ?0 and c <= ?9 do
               "*"
             else
               <<c>>
             end
           else
             _ -> []
           end
           """))
  end

  test "preserves inner if/else that is not the for else (no longer flags)" do
    assert analyze(fix("""
           for <<c <- "hello">> do
             if c >= ?0 and c <= ?9 do
               "*"
             else
               <<c>>
             end
           else
             _ -> []
           end
           """)) == []
  end
end
