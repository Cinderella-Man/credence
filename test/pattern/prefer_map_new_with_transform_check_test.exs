defmodule Credence.Pattern.PreferMapNewWithTransformCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapNewWithTransform

  test "flags Enum.map |> Map.new pipe pattern" do
    assert flagged?(PreferMapNewWithTransform, """
           Enum.map(1..5, fn i -> {i, i * i} end) |> Map.new()
           """)
  end

  test "flags multi-line pipe pattern" do
    assert flagged?(PreferMapNewWithTransform, """
           1..5
           |> Enum.map(fn i -> {i, i * i} end)
           |> Map.new()
           """)
  end

  test "flags nested Map.new(Enum.map(...)) pattern" do
    assert flagged?(PreferMapNewWithTransform, """
           Map.new(Enum.map(1..5, fn i -> {i, i * i} end))
           """)
  end

  test "leaves Map.new/2 alone (already idiomatic)" do
    assert clean?(PreferMapNewWithTransform, """
           Map.new(1..5, fn i -> {i, i * i} end)
           """)
  end

  test "leaves Enum.map alone (no Map.new)" do
    assert clean?(PreferMapNewWithTransform, """
           Enum.map(1..5, fn i -> {i, i * i} end)
           """)
  end

  test "leaves Map.new/1 alone (with explicit enumerable)" do
    assert clean?(PreferMapNewWithTransform, """
           Map.new(1..5)
           """)
  end

  test "leaves unrelated pipe alone" do
    assert clean?(PreferMapNewWithTransform, """
           1..5 |> Enum.map(fn i -> i * i end) |> Enum.sum()
           """)
  end
end
