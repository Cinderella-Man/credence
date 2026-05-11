defmodule Credence.Pattern.NoEnumAtNegativeIndexFixTest do
  use ExUnit.Case

  defp fix(code) do
    result = Credence.Pattern.NoEnumAtNegativeIndex.fix(code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ── Single -1 → List.last ──────────────────────────────────────────────

  describe "single -1 assignment → List.last" do
    test "standalone assignment" do
      input =
        "defmodule M do\n  def f(list) do\n    last = Enum.at(list, -1)\n    last\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(list) do\n    last = List.last(list)\n    last\n  end\nend\n"

      assert fix(input) == expected
    end

    test "piped assignment" do
      input =
        "defmodule M do\n  def f(list) do\n    last = list |> Enum.at(-1)\n    last\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(list) do\n    last = List.last(list)\n    last\n  end\nend\n"

      assert fix(input) == expected
    end

    test "two -1 on different lists" do
      input =
        "defmodule M do\n  def f(a, b) do\n    x = Enum.at(a, -1)\n    y = Enum.at(b, -1)\n    {x, y}\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(a, b) do\n    x = List.last(a)\n    y = List.last(b)\n    {x, y}\n  end\nend\n"

      assert fix(input) == expected
    end
  end

  describe "inline -1 (non-assignment) → List.last" do
    test "in if condition" do
      input =
        "defmodule M do\n  def f(list) do\n    if Enum.at(list, -1) == :done, do: :ok, else: :wait\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(list) do\n    if List.last(list) == :done, do: :ok, else: :wait\n  end\nend\n"

      assert fix(input) == expected
    end

    test "piped in expression" do
      input =
        "defmodule M do\n  def f(list), do: list |> Enum.sort() |> Enum.at(-1)\nend\n"

      expected =
        "defmodule M do\n  def f(list), do: list |> Enum.sort() |> List.last()\nend\n"

      assert fix(input) == expected
    end
  end

  # ── Grouped reverse + pattern match ─────────────────────────────────────

  describe "grouped reverse + pattern match" do
    test "two accesses same list" do
      input =
        "defmodule M do\n  def f(sorted) do\n    last = Enum.at(sorted, -1)\n    second = Enum.at(sorted, -2)\n    {last, second}\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(sorted) do\n    sorted_reversed = Enum.reverse(sorted)\n    [last, second | _] = sorted_reversed\n    {last, second}\n  end\nend\n"

      assert fix(input) == expected
    end

    test "three accesses same list" do
      input =
        "defmodule M do\n  def f(nums) do\n    a = Enum.at(nums, -1)\n    b = Enum.at(nums, -2)\n    c = Enum.at(nums, -3)\n    {a, b, c}\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(nums) do\n    nums_reversed = Enum.reverse(nums)\n    [a, b, c | _] = nums_reversed\n    {a, b, c}\n  end\nend\n"

      assert fix(input) == expected
    end

    test "non-consecutive indices fill gaps with _" do
      input =
        "defmodule M do\n  def f(list) do\n    last = Enum.at(list, -1)\n    third = Enum.at(list, -3)\n    {last, third}\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(list) do\n    list_reversed = Enum.reverse(list)\n    [last, _, third | _] = list_reversed\n    {last, third}\n  end\nend\n"

      assert fix(input) == expected
    end

    test "single -2 gets reverse + pattern" do
      input =
        "defmodule M do\n  def f(list) do\n    second = Enum.at(list, -2)\n    second\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(list) do\n    list_reversed = Enum.reverse(list)\n    [_, second | _] = list_reversed\n    second\n  end\nend\n"

      assert fix(input) == expected
    end

    test "single -3 gets reverse + pattern" do
      input =
        "defmodule M do\n  def f(list) do\n    val = Enum.at(list, -3)\n    val\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(list) do\n    list_reversed = Enum.reverse(list)\n    [_, _, val | _] = list_reversed\n    val\n  end\nend\n"

      assert fix(input) == expected
    end

    test "depth 5 with gaps" do
      input =
        "defmodule M do\n  def f(list) do\n    a = Enum.at(list, -1)\n    e = Enum.at(list, -5)\n    {a, e}\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(list) do\n    list_reversed = Enum.reverse(list)\n    [a, _, _, _, e | _] = list_reversed\n    {a, e}\n  end\nend\n"

      assert fix(input) == expected
    end

    test "pipe-form assignments grouped" do
      input =
        "defmodule M do\n  def f(list) do\n    last = list |> Enum.at(-1)\n    second = list |> Enum.at(-2)\n    {last, second}\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(list) do\n    list_reversed = Enum.reverse(list)\n    [last, second | _] = list_reversed\n    {last, second}\n  end\nend\n"

      assert fix(input) == expected
    end
  end

  # ── Scope isolation ─────────────────────────────────────────────────────

  describe "scope isolation" do
    test "different functions not grouped" do
      input =
        "defmodule M do\n  def foo(list) do\n    a = Enum.at(list, -1)\n    a\n  end\n\n  def bar(list) do\n    b = Enum.at(list, -2)\n    b\n  end\nend\n"

      expected =
        "defmodule M do\n  def foo(list) do\n    a = List.last(list)\n    a\n  end\n\n  def bar(list) do\n    list_reversed = Enum.reverse(list)\n    [_, b | _] = list_reversed\n    b\n  end\nend\n"

      assert fix(input) == expected
    end

    test "different list variables independent" do
      input =
        "defmodule M do\n  def f(a, b) do\n    x = Enum.at(a, -1)\n    y = Enum.at(b, -1)\n    {x, y}\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(a, b) do\n    x = List.last(a)\n    y = List.last(b)\n    {x, y}\n  end\nend\n"

      assert fix(input) == expected
    end

    test "same list grouped + different list standalone" do
      input =
        "defmodule M do\n  def f(sorted, other) do\n    last = Enum.at(sorted, -1)\n    second = Enum.at(sorted, -2)\n    other_last = Enum.at(other, -1)\n    {last, second, other_last}\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(sorted, other) do\n    sorted_reversed = Enum.reverse(sorted)\n    [last, second | _] = sorted_reversed\n    other_last = List.last(other)\n    {last, second, other_last}\n  end\nend\n"

      assert fix(input) == expected
    end
  end

  # ── Expression-form negative indices (non-assignment) ───────────────────
  # These generate temporary variable names for the reverse + pattern match,
  # so exact output depends on implementation internals. Using targeted
  # assertions on structure rather than exact string match.

  describe "expression-form negative indices" do
    test "two negative indices in multiplication" do
      input =
        "defmodule M do\n  def f(sorted) do\n    result = Enum.at(sorted, -1) * Enum.at(sorted, -2)\n    result\n  end\nend\n"

      fixed = fix(input)
      assert fixed =~ "Enum.reverse(sorted)"
      refute fixed =~ "Enum.at(sorted, -1)"
      refute fixed =~ "Enum.at(sorted, -2)"
    end

    test "single -2 in expression gets reverse + pattern" do
      input =
        "defmodule M do\n  def f(sorted) do\n    result = Enum.at(sorted, -2) + 1\n    result\n  end\nend\n"

      fixed = fix(input)
      assert fixed =~ "Enum.reverse(sorted)"
      refute fixed =~ "Enum.at(sorted, -2)"
    end

    test "single -1 in expression becomes List.last" do
      input =
        "defmodule M do\n  def f(list) do\n    result = Enum.at(list, -1) + 1\n    result\n  end\nend\n"

      expected =
        "defmodule M do\n  def f(list) do\n    result = List.last(list) + 1\n    result\n  end\nend\n"

      assert fix(input) == expected
    end
  end

  # ── No-ops and edge cases ───────────────────────────────────────────────

  describe "no-ops" do
    test "positive index unchanged" do
      input =
        "defmodule M do\n  def f(list) do\n    first = Enum.at(list, 0)\n    first\n  end\nend\n"

      assert fix(input) == input
    end

    test "variable index unchanged" do
      input =
        "defmodule M do\n  def f(list, i) do\n    val = Enum.at(list, i)\n    val\n  end\nend\n"

      assert fix(input) == input
    end

    test "no Enum.at at all" do
      input = "defmodule M do\n  def f(list), do: List.last(list)\nend\n"
      assert fix(input) == input
    end

    test "complex list expression skipped" do
      input =
        "defmodule M do\n  def f(data) do\n    a = Enum.at(Map.get(data, :items), -1)\n    a\n  end\nend\n"

      assert fix(input) == input
    end

    test "duplicate LHS variable names skipped for grouping" do
      input =
        "defmodule M do\n  def f(list) do\n    x = Enum.at(list, -1)\n    x = Enum.at(list, -2)\n    x\n  end\nend\n"

      fixed = fix(input)
      # Group invalid (duplicate :x), but -1 still caught by inline fix
      assert fixed =~ "List.last(list)"
    end
  end
end
