defmodule Credence.Syntax.NoElseIfFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoElseIf

  defp analyze(code), do: NoElseIf.analyze(code)
  defp fix(code), do: NoElseIf.fix(code)

  test "fixes the syntax error" do
    input = """
    if n == 0 do
      list
    else if n >= length(list) do
      []
    else
      List.take(list, length(list) - n)
    end
    """

    expected = """
    cond do
      n == 0 -> list
      n >= length(list) -> []
      true -> List.take(list, length(list) - n)
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             if n == 0 do
               list
             else if n >= length(list) do
               []
             else
               List.take(list, length(list) - n)
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             if n == 0 do
               list
             else if n >= length(list) do
               []
             else
               List.take(list, length(list) - n)
             end
             """)
           )
  end

  test "fixes else branch with comment-only body (inserts nil)" do
    input = """
    if n == 0 do
      [1]
    else if n == 1 do
      [1, 1]
    else
      # comment only, no expression
    end
    """

    expected = """
    cond do
      n == 0 -> [1]
      n == 1 -> [1, 1]
      true -> nil
        # comment only, no expression
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "comment-only else fix is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             if n == 0 do
               [1]
             else if n == 1 do
               [1, 1]
             else
               # comment only, no expression
             end
             """)
           )
  end

  test "comment-only else fix no longer flags" do
    assert analyze(
             fix("""
             if n == 0 do
               [1]
             else if n == 1 do
               [1, 1]
             else
               # comment only, no expression
             end
             """)
           ) == []
  end

  # A nested `if` without a trailing `else` evaluates to `nil` when no branch
  # matches, but a `cond` with no `true` clause raises `CondClauseError`. The fix
  # appends `true -> nil` so the rewrite keeps the original `nil` answer.
  test "no trailing else: appends true -> nil to preserve the nil result" do
    input = """
    if a do
      p
    else if b do
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
             else if b do
               q
             end
             """)
           )
  end

  # When a branch condition cannot be extracted cleanly, substituting a guessed
  # `true ->` clause would silently change behaviour (it would unconditionally
  # take that branch). The fix refuses these shapes and leaves the source intact
  # instead, so the code stays flagged as broken rather than miscompiled.

  test "leaves a multi-line if condition untouched (cannot extract cleanly)" do
    input = """
    if a and
         b do
      list
    else if c do
      []
    else
      other
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves a multi-line else-if condition untouched" do
    input = """
    if a do
      p
    else if b and
         c do
      q
    else
      r
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves an if line with a trailing comment after do untouched" do
    input = """
    if a do # note
      p
    else if b do
      q
    else
      r
    end
    """

    confirm_fix(fix(input), input)
  end

  test "leaves a one-liner else-if (`, do:`) untouched" do
    input = """
    if a do
      p
    else if b, do: q
    else
      r
    end
    """

    confirm_fix(fix(input), input)
  end
end
