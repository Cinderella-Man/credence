defmodule Credence.Semantic.UndefinedFunctionFixTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedFunction

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  # ── module.function renames (existing) ─────────────────────────

  describe "Enum.last → List.last" do
    test "direct call" do
      assert fix("Enum.last(list)", "Enum.last/1 is undefined or private") == "List.last(list)"
    end

    test "piped" do
      assert fix("list |> Enum.last()", "Enum.last/0 is undefined or private") ==
               "list |> List.last()"
    end

    test "only on reported line" do
      input = "Enum.at(x, 0)\nEnum.last(x)\nEnum.count(x)"

      assert fix(input, "Enum.last/1 is undefined or private", 2) ==
               "Enum.at(x, 0)\nList.last(x)\nEnum.count(x)"
    end
  end

  describe "List.reverse → Enum.reverse" do
    test "direct call" do
      assert fix("List.reverse(items)", "List.reverse/1 is undefined or private") ==
               "Enum.reverse(items)"
    end

    test "piped" do
      assert fix("items |> List.reverse()", "List.reverse/1 is undefined or private") ==
               "items |> Enum.reverse()"
    end

    test "mid-pipeline" do
      assert fix(
               "nums |> Enum.sort() |> List.reverse() |> hd()",
               "List.reverse/1 is undefined or private"
             ) ==
               "nums |> Enum.sort() |> Enum.reverse() |> hd()"
    end
  end

  describe "Enum.partition → Enum.split_with (deprecated)" do
    test "direct call" do
      assert fix(
               "Enum.partition(list, &is_integer/1)",
               "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead"
             ) == "Enum.split_with(list, &is_integer/1)"
    end

    test "piped" do
      assert fix(
               "list |> Enum.partition(fn {_v, i} -> Integer.is_even(i) end)",
               "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead"
             ) == "list |> Enum.split_with(fn {_v, i} -> Integer.is_even(i) end)"
    end

    test "only on reported line" do
      input = "x = Enum.map(list, &f/1)\n{a, b} = Enum.partition(list, &pred/1)"

      assert fix(input, "Enum.partition/2 is deprecated. Use Enum.split_with/2 instead", 2) ==
               "x = Enum.map(list, &f/1)\n{a, b} = Enum.split_with(list, &pred/1)"
    end
  end

  # ── hallucinated Float infinity → atom literals ────────────────

  describe "Float.NegInfinity() → :neg_infinity" do
    test "direct call" do
      assert fix("Float.NegInfinity()", "Float.NegInfinity/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "as function argument" do
      assert fix(
               "validate(root, Float.NegInfinity(), Float.PositiveInfinity())",
               "Float.NegInfinity/0 is undefined or private"
             ) == "validate(root, :neg_infinity, Float.PositiveInfinity())"
    end
  end

  describe "Float.PositiveInfinity() → :infinity" do
    test "direct call" do
      assert fix("Float.PositiveInfinity()", "Float.PositiveInfinity/0 is undefined or private") ==
               ":infinity"
    end

    test "as function argument" do
      assert fix(
               "validate(root, :neg_infinity, Float.PositiveInfinity())",
               "Float.PositiveInfinity/0 is undefined or private"
             ) == "validate(root, :neg_infinity, :infinity)"
    end
  end

  describe "Float.NegInf() → :neg_infinity" do
    test "direct call" do
      assert fix("Float.NegInf()", "Float.NegInf/0 is undefined or private") == ":neg_infinity"
    end
  end

  describe "Float.Infinity() → :infinity" do
    test "direct call" do
      assert fix("Float.Infinity()", "Float.Infinity/0 is undefined or private") == ":infinity"
    end
  end

  # ── hallucinated Integer bounds → atom literals ────────────────

  describe "Integer.min_value() → :neg_infinity" do
    test "direct call" do
      assert fix("Integer.min_value()", "Integer.min_value/0 is undefined or private") ==
               ":neg_infinity"
    end

    test "in module attribute" do
      assert fix("@min_bound Integer.min_value()", "Integer.min_value/0 is undefined or private") ==
               "@min_bound :neg_infinity"
    end
  end

  describe "Integer.max_value() → :infinity" do
    test "direct call" do
      assert fix("Integer.max_value()", "Integer.max_value/0 is undefined or private") ==
               ":infinity"
    end

    test "in module attribute" do
      assert fix("@max_bound Integer.max_value()", "Integer.max_value/0 is undefined or private") ==
               "@max_bound :infinity"
    end
  end

  # ── hallucinated List.pop → List.last ──────────────────────────

  describe "List.pop → List.last" do
    test "direct call" do
      assert fix("List.pop(items)", "List.pop/1 is undefined or private") == "List.last(items)"
    end

    test "piped" do
      assert fix("items |> List.pop()", "List.pop/1 is undefined or private") ==
               "items |> List.last()"
    end

    test "mid-pipeline" do
      assert fix(
               "acc |> List.pop() |> elem(0)",
               "List.pop/1 is undefined or private"
             ) == "acc |> List.last() |> elem(0)"
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "unknown function unchanged" do
      source = "MyModule.foo(x)"
      assert fix(source, "MyModule.foo/1 is undefined or private") == source
    end

    test "unknown Float function unchanged" do
      source = "Float.unknown_thing()"
      assert fix(source, "Float.unknown_thing/0 is undefined or private") == source
    end
  end
end
