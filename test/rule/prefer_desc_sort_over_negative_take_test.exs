defmodule Credence.Rule.PreferDescSortOverNegativeTakeTest do
  use ExUnit.Case

  alias Credence.Rule.PreferDescSortOverNegativeTake

  test "flags Enum.sort |> Enum.take(-n)" do
    code = """
    nums
    |> Enum.sort()
    |> Enum.take(-3)
    """

    {:ok, ast} = Code.string_to_quoted(code)

    issues = PreferDescSortOverNegativeTake.check(ast, [])

    assert length(issues) == 1

    assert Enum.any?(issues, fn issue ->
             String.contains?(issue.message, "Prefer `Enum.sort(nums, :desc)")
           end)
  end

  test "does not flag Enum.sort(:desc) |> Enum.take(n)" do
    code = """
    nums
    |> Enum.sort(:desc)
    |> Enum.take(3)
    """

    {:ok, ast} = Code.string_to_quoted(code)

    issues = PreferDescSortOverNegativeTake.check(ast, [])

    assert issues == []
  end

  test "does not flag Enum.sort |> Enum.take(positive n)" do
    code = """
    nums
    |> Enum.sort()
    |> Enum.take(3)
    """

    {:ok, ast} = Code.string_to_quoted(code)

    issues = PreferDescSortOverNegativeTake.check(ast, [])

    assert issues == []
  end
end
