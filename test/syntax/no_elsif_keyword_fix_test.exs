defmodule Credence.Syntax.NoElsifKeywordFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoElsifKeyword

  defp analyze(code), do: NoElsifKeyword.analyze(code)
  defp fix(code), do: NoElsifKeyword.fix(code)

  test "fixes the syntax error" do
    input = """
    if x == nil do
      {:error, :missing}
    elsif y <= 0 do
      {:error, :invalid}
    elsif y > 100 do
      {:error, :too_large}
    else
      {:ok, y}
    end
    """

    expected = """
    cond do
      x == nil -> {:error, :missing}
      y <= 0 -> {:error, :invalid}
      y > 100 -> {:error, :too_large}
      true -> {:ok, y}
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             if x == nil do
               {:error, :missing}
             elsif y <= 0 do
               {:error, :invalid}
             elsif y > 100 do
               {:error, :too_large}
             else
               {:ok, y}
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             if x == nil do
               {:error, :missing}
             elsif y <= 0 do
               {:error, :invalid}
             elsif y > 100 do
               {:error, :too_large}
             else
               {:ok, y}
             end
             """)
           )
  end

  # A trailing `else` without one evaluates to `nil` when no branch matches,
  # but `cond` raises `CondClauseError`. The fix appends `true -> nil` so the
  # rewrite keeps the original `nil` answer.
  test "no trailing else: appends true -> nil to preserve the nil result" do
    input = """
    if a do
      p
    elsif b do
      q
    end
    """

    expected = """
    cond do
      a -> p
      b -> q
      true -> nil
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "no-trailing-else fix is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             if a do
               p
             elsif b do
               q
             end
             """)
           )
  end

  test "no-trailing-else fix no longer flags" do
    assert analyze(
             fix("""
             if a do
               p
             elsif b do
               q
             end
             """)
           ) == []
  end
end
