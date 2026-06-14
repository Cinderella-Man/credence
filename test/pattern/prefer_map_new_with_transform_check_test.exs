defmodule Credence.Pattern.PreferMapNewWithTransformCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapNewWithTransform

  test "flags Enum.map |> Map.new pipe pattern" do
    assert flagged?(
             PreferMapNewWithTransform,
             "Enum.map(1..5, fn i -> {i, i * i} end) |> Map.new()"
           )
  end

  test "flags multi-line pipe pattern" do
    assert flagged?(PreferMapNewWithTransform, """
           1..5
           |> Enum.map(fn i -> {i, i * i} end)
           |> Map.new()
           """)
  end

  test "flags nested Map.new(Enum.map(...)) pattern" do
    assert flagged?(PreferMapNewWithTransform, "Map.new(Enum.map(1..5, fn i -> {i, i * i} end))")
  end

  # Regression: the pipe form used to emit an issue with no `:line` (it passed the
  # whole `Enum.map` node where a meta keyword list was expected), leaving the
  # finding unlocatable. Every form must report the line of the offending step.
  test "single-line pipe form reports the line" do
    assert [%{meta: %{line: 1}}] =
             check(
               PreferMapNewWithTransform,
               "Enum.map(1..5, fn i -> {i, i * i} end) |> Map.new()"
             )
  end

  test "multi-line pipe form reports the Enum.map line" do
    assert [%{meta: %{line: 2}}] =
             check(PreferMapNewWithTransform, """
             1..5
             |> Enum.map(fn i -> {i, i * i} end)
             |> Map.new()
             """)
  end

  test "nested form reports the line" do
    assert [%{meta: %{line: 1}}] =
             check(PreferMapNewWithTransform, "Map.new(Enum.map(1..5, fn i -> {i, i * i} end))")
  end

  test "leaves Map.new/2 alone (already idiomatic)" do
    assert clean?(PreferMapNewWithTransform, "Map.new(1..5, fn i -> {i, i * i} end)")
  end

  test "leaves Enum.map alone (no Map.new)" do
    assert clean?(PreferMapNewWithTransform, "Enum.map(1..5, fn i -> {i, i * i} end)")
  end

  test "leaves Map.new/1 alone (with explicit enumerable)" do
    assert clean?(PreferMapNewWithTransform, "Map.new(1..5)")
  end

  test "leaves unrelated pipe alone" do
    assert clean?(PreferMapNewWithTransform, "1..5 |> Enum.map(fn i -> i * i end) |> Enum.sum()")
  end
end
