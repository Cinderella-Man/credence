defmodule Credence.Syntax.NoElifKeywordFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoElifKeyword

  defp analyze(code), do: NoElifKeyword.analyze(code)
  defp fix(code), do: NoElifKeyword.fix(code)

  test "fixes the syntax error" do
    input = """
    if sequence <= last_seq do
      {:reply, {:ok, :duplicate}, state}
    elif sequence > last_seq + 1 do
      {:reply, {:ok, :buffered}, state}
    else
      {:reply, {:ok, :received}, state}
    end
    """

    expected = """
    cond do
      sequence <= last_seq -> {:reply, {:ok, :duplicate}, state}
      sequence > last_seq + 1 -> {:reply, {:ok, :buffered}, state}
      true -> {:reply, {:ok, :received}, state}
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             if sequence <= last_seq do
               {:reply, {:ok, :duplicate}, state}
             elif sequence > last_seq + 1 do
               {:reply, {:ok, :buffered}, state}
             else
               {:reply, {:ok, :received}, state}
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             if sequence <= last_seq do
               {:reply, {:ok, :duplicate}, state}
             elif sequence > last_seq + 1 do
               {:reply, {:ok, :buffered}, state}
             else
               {:reply, {:ok, :received}, state}
             end
             """)
           )
  end

  test "no trailing else: appends true -> nil to preserve the nil result" do
    input = """
    if a do
      p
    elif b do
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
             elif b do
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
             elif b do
               q
             end
             """)
           ) == []
  end

  test "fixes multiple elif branches" do
    input = """
    if a do
      1
    elif b do
      2
    elif c do
      3
    else
      4
    end
    """

    expected = """
    cond do
      a -> 1
      b -> 2
      c -> 3
      true -> 4
    end
    """

    confirm_fix(fix(input), expected)
  end
end
