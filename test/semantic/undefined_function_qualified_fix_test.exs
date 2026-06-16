defmodule Credence.Semantic.UndefinedFunction.QualifiedFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.Semantic.UndefinedFunction
  alias Qualified

  defp fix(source, message, line \\ 1) do
    UndefinedFunction.fix(source, %{severity: :warning, message: message, position: {line, 1}})
  end

  # ── renames ────────────────────────────────────────────────────

  describe "Enum.last → List.last" do
    test "direct call" do
      confirm_fix(
        fix(
          "Enum.last(list)",
          """
          Enum.last/1 is undefined or private
          """
        ),
        "List.last(list)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "list |> Enum.last()",
          """
          Enum.last/0 is undefined or private
          """
        ),
        "list |> List.last()"
      )
    end

    test "only on reported line" do
      input = """
      Enum.at(x, 0)
      Enum.last(x)
      Enum.count(x)
      """

      confirm_fix(
        fix(
          input,
          """
          Enum.last/1 is undefined or private
          """,
          2
        ),
        """
        Enum.at(x, 0)
        List.last(x)
        Enum.count(x)
        """
      )
    end
  end

  describe "List.reverse → Enum.reverse" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.reverse(items)",
          """
          List.reverse/1 is undefined or private
          """
        ),
        "Enum.reverse(items)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "items |> List.reverse()",
          """
          List.reverse/1 is undefined or private
          """
        ),
        "items |> Enum.reverse()"
      )
    end

    test "mid-pipeline" do
      confirm_fix(
        fix(
          "nums |> Enum.sort() |> List.reverse() |> hd()",
          """
          List.reverse/1 is undefined or private
          """
        ),
        "nums |> Enum.sort() |> Enum.reverse() |> hd()"
      )
    end
  end

  describe "Enum.partition → Enum.split_with (deprecated)" do
    test "direct call" do
      confirm_fix(
        fix(
          "Enum.partition(list, &is_integer/1)",
          """
          Enum.partition/2 is deprecated. Use Enum.split_with/2 instead
          """
        ),
        "Enum.split_with(list, &is_integer/1)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "list |> Enum.partition(fn {_v, i} -> Integer.is_even(i) end)",
          """
          Enum.partition/2 is deprecated. Use Enum.split_with/2 instead
          """
        ),
        "list |> Enum.split_with(fn {_v, i} -> Integer.is_even(i) end)"
      )
    end

    test "only on reported line" do
      input = """
      x = Enum.map(list, &f/1)
      {a, b} = Enum.partition(list, &pred/1)
      """

      confirm_fix(
        fix(
          input,
          """
          Enum.partition/2 is deprecated. Use Enum.split_with/2 instead
          """,
          2
        ),
        """
        x = Enum.map(list, &f/1)
        {a, b} = Enum.split_with(list, &pred/1)
        """
      )
    end
  end

  describe "List.pop → List.last" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.pop(items)",
          """
          List.pop/1 is undefined or private
          """
        ),
        "List.last(items)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "items |> List.pop()",
          """
          List.pop/1 is undefined or private
          """
        ),
        "items |> List.last()"
      )
    end

    test "mid-pipeline" do
      confirm_fix(
        fix(
          "acc |> List.pop() |> elem(0)",
          """
          List.pop/1 is undefined or private
          """
        ),
        "acc |> List.last() |> elem(0)"
      )
    end
  end

  describe "List.drop → Enum.drop" do
    test "direct call" do
      confirm_fix(
        fix(
          "List.drop(items, 3)",
          """
          List.drop/2 is undefined or private
          """
        ),
        "Enum.drop(items, 3)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "items |> List.drop(1)",
          """
          List.drop/2 is undefined or private
          """
        ),
        "items |> Enum.drop(1)"
      )
    end

    test "nested" do
      confirm_fix(
        fix(
          "List.last(sorted) * List.second(List.drop(sorted, n))",
          """
          List.drop/2 is undefined or private
          """
        ),
        "List.last(sorted) * List.second(Enum.drop(sorted, n))"
      )
    end
  end

  describe "Enum.cycle → Stream.cycle" do
    test "direct call" do
      confirm_fix(
        fix(
          "Enum.cycle(items)",
          """
          Enum.cycle/1 is undefined or private
          """
        ),
        "Stream.cycle(items)"
      )
    end

    test "piped" do
      confirm_fix(
        fix(
          "items |> Enum.cycle()",
          """
          Enum.cycle/1 is undefined or private
          """
        ),
        "items |> Stream.cycle()"
      )
    end

    test "inside expression" do
      confirm_fix(
        fix(
          "Enum.flat_map(1..10, &Enum.cycle([&1]))",
          """
          Enum.cycle/1 is undefined or private
          """
        ),
        "Enum.flat_map(1..10, &Stream.cycle([&1]))"
      )
    end
  end

  # ── literals ───────────────────────────────────────────────────

  describe "Float.NegInfinity → :neg_infinity" do
    test "with parens" do
      confirm_fix(
        fix(
          "Float.NegInfinity()",
          """
          Float.NegInfinity/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end

    test "without parens" do
      confirm_fix(
        fix(
          "Float.NegInfinity",
          """
          Float.NegInfinity/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end

    test "as function argument" do
      confirm_fix(
        fix(
          "validate(root, Float.NegInfinity(), Float.PositiveInfinity())",
          """
          Float.NegInfinity/0 is undefined or private
          """
        ),
        "validate(root, :neg_infinity, Float.PositiveInfinity())"
      )
    end
  end

  describe "Float.PositiveInfinity → :infinity" do
    test "with parens" do
      confirm_fix(
        fix(
          "Float.PositiveInfinity()",
          """
          Float.PositiveInfinity/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end

    test "without parens" do
      confirm_fix(
        fix(
          "Float.PositiveInfinity",
          """
          Float.PositiveInfinity/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end

    test "as function argument" do
      confirm_fix(
        fix(
          "validate(root, :neg_infinity, Float.PositiveInfinity())",
          """
          Float.PositiveInfinity/0 is undefined or private
          """
        ),
        "validate(root, :neg_infinity, :infinity)"
      )
    end
  end

  describe "Float.NegInf → :neg_infinity" do
    test "direct call" do
      confirm_fix(
        fix(
          "Float.NegInf()",
          """
          Float.NegInf/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end
  end

  describe "Float.Infinity → :infinity" do
    test "direct call" do
      confirm_fix(
        fix(
          "Float.Infinity()",
          """
          Float.Infinity/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end
  end

  describe "Float.inf → :infinity / -Float.inf → :neg_infinity" do
    test "negated without parens" do
      confirm_fix(
        fix(
          "max_num = -Float.inf",
          """
          Float.inf/0 is undefined or private
          """
        ),
        "max_num = :neg_infinity"
      )
    end

    test "negated with parens" do
      confirm_fix(
        fix(
          "max_num = -Float.inf()",
          """
          Float.inf/0 is undefined or private
          """
        ),
        "max_num = :neg_infinity"
      )
    end

    test "positive without parens" do
      confirm_fix(
        fix(
          "upper = Float.inf",
          """
          Float.inf/0 is undefined or private
          """
        ),
        "upper = :infinity"
      )
    end

    test "positive with parens" do
      confirm_fix(
        fix(
          "upper = Float.inf()",
          """
          Float.inf/0 is undefined or private
          """
        ),
        "upper = :infinity"
      )
    end

    test "realistic context" do
      code = """
          max_num = -Float.inf
          second_max_num = -Float.inf
      """

      confirm_fix(
        fix(
          code,
          """
          Float.inf/0 is undefined or private
          """,
          1
        ),
        """
            max_num = :neg_infinity
            second_max_num = -Float.inf
        """
      )
    end
  end

  describe "Integer.min_value → :neg_infinity" do
    test "with parens" do
      confirm_fix(
        fix(
          "Integer.min_value()",
          """
          Integer.min_value/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end

    test "without parens" do
      confirm_fix(
        fix(
          "Integer.min_value",
          """
          Integer.min_value/0 is undefined or private
          """
        ),
        ":neg_infinity"
      )
    end

    test "in module attribute" do
      confirm_fix(
        fix(
          "@min_bound Integer.min_value()",
          """
          Integer.min_value/0 is undefined or private
          """
        ),
        "@min_bound :neg_infinity"
      )
    end
  end

  describe "Integer.max_value → :infinity" do
    test "with parens" do
      confirm_fix(
        fix(
          "Integer.max_value()",
          """
          Integer.max_value/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end

    test "without parens" do
      confirm_fix(
        fix(
          "Integer.max_value",
          """
          Integer.max_value/0 is undefined or private
          """
        ),
        ":infinity"
      )
    end

    test "in module attribute" do
      confirm_fix(
        fix(
          "@max_bound Integer.max_value()",
          """
          Integer.max_value/0 is undefined or private
          """
        ),
        "@max_bound :infinity"
      )
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "qualified: no-ops" do
    test "unknown function unchanged" do
      source = "MyModule.foo(x)"

      confirm_fix(
        fix(source, """
        MyModule.foo/1 is undefined or private
        """),
        source
      )
    end

    test "unknown Float function unchanged" do
      source = "Float.unknown_thing()"

      confirm_fix(
        fix(source, """
        Float.unknown_thing/0 is undefined or private
        """),
        source
      )
    end
  end
end
