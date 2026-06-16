defmodule Credence.Pattern.PreferMapNewWithTransformFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMapNewWithTransform

  test "rewrites Enum.map |> Map.new pipe pattern" do
    input = "Enum.map(1..5, fn i -> {i, i * i} end) |> Map.new()"

    expected = "Map.new(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, input), expected)
  end

  test "rewrites multi-line pipe pattern" do
    input = """
    1..5
    |> Enum.map(fn i -> {i, i * i} end)
    |> Map.new()
    """

    expected = "Map.new(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, input), expected)
  end

  test "rewrites nested Map.new(Enum.map(...)) pattern" do
    input = "Map.new(Enum.map(1..5, fn i -> {i, i * i} end))"

    expected = "Map.new(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, input), expected)
  end

  test "preserves surrounding code" do
    input = """
    defmodule Example do
      def build_map do
        1..5
        |> Enum.map(fn i -> {i, i * i} end)
        |> Map.new()
      end
    end
    """

    expected = """
    defmodule Example do
      def build_map do
        Map.new(1..5, fn i -> {i, i * i} end)
      end
    end
    """

    confirm_fix(fix(PreferMapNewWithTransform, input), expected)
  end

  test "does not change code without the pattern" do
    code = "Map.new(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, code), code)
  end

  test "does not change Enum.map alone" do
    code = "Enum.map(1..5, fn i -> {i, i * i} end)"

    confirm_fix(fix(PreferMapNewWithTransform, code), code)
  end

  test "does not change Map.new/1 alone" do
    code = "Map.new(1..5)"

    confirm_fix(fix(PreferMapNewWithTransform, code), code)
  end

  # Head-of-pipe 1-arg Enum.map has no collection to recover, so the fix is a
  # no-op — and the check is narrowed to not flag it, keeping the two in agreement.
  test "does not change head-of-pipe 1-arg Enum.map" do
    code = "Enum.map(fn i -> {i, i} end) |> Map.new()"

    confirm_fix(fix(PreferMapNewWithTransform, code), code)
  end
end
