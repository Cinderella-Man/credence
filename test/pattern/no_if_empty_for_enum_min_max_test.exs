defmodule Credence.Pattern.NoIfEmptyForEnumMinMaxTest do
  use ExUnit.Case

  alias Credence.Pattern.NoIfEmptyForEnumMinMax

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoIfEmptyForEnumMinMax.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoIfEmptyForEnumMinMax, code, [])

  describe "check" do
    test "detects if var == [] then default else Enum.min(var)" do
      code = """
      defmodule Bad do
        def run(lengths) do
          if lengths == [], do: 0, else: Enum.min(lengths)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_if_empty_for_enum_min_max
    end

    test "detects if var == [] then default else Enum.max(var)" do
      code = """
      defmodule Bad do
        def run(lengths) do
          if lengths == [], do: 0, else: Enum.max(lengths)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects if var != [] then Enum.min(var) else default" do
      code = """
      defmodule Bad do
        def run(lengths) do
          if lengths != [], do: Enum.min(lengths), else: 0
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects if var != [] then Enum.max(var) else default" do
      code = """
      defmodule Bad do
        def run(lengths) do
          if lengths != [], do: Enum.max(lengths), else: -1
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT fire on code that already uses Enum.min/2 with default" do
      code = """
      defmodule Good do
        def run(lengths) do
          Enum.min(lengths, fn -> 0 end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT fire on plain Enum.min/1 call" do
      code = """
      defmodule Good do
        def run(lengths) do
          Enum.min(lengths)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT fire when condition is not empty list check" do
      code = """
      defmodule Good do
        def run(lengths, threshold) do
          if lengths == threshold, do: 0, else: Enum.min(lengths)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT fire when Enum.min uses different variable than condition" do
      code = """
      defmodule Good do
        def run(a, b) do
          if a == [], do: 0, else: Enum.min(b)
        end
      end
      """

      assert check(code) == []
    end

    test "detects case list do [] -> default; v -> Enum.max(v) end" do
      code = """
      defmodule Bad do
        def run(lengths) do
          case lengths do
            [] -> -1
            filtered -> Enum.max(filtered)
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_if_empty_for_enum_min_max
    end

    test "detects case list do [] -> default; v -> Enum.min(v) end" do
      code = """
      defmodule Bad do
        def run(lengths) do
          case lengths do
            [] -> 0
            filtered -> Enum.min(filtered)
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects case with reversed clause order" do
      code = """
      defmodule Bad do
        def run(lengths) do
          case lengths do
            filtered -> Enum.max(filtered)
            [] -> -1
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects case in pipeline context" do
      code = """
      defmodule Bad do
        def run(numbers, target) do
          numbers
          |> Enum.filter(&(&1 < target))
          |> case do
            [] -> -1
            filtered -> Enum.max(filtered)
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT fire on case with 3 clauses" do
      code = """
      defmodule Good do
        def run(lengths) do
          case lengths do
            [] -> -1
            [single] -> single
            filtered -> Enum.max(filtered)
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT fire on case with Enum.max/2 default" do
      code = """
      defmodule Good do
        def run(lengths) do
          case lengths do
            [] -> -1
            filtered -> Enum.max(filtered, fn -> 0 end)
          end
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "rewrites if var == [] then 0 else Enum.min(var) to Enum.min/2" do
      code = """
      if lengths == [], do: 0, else: Enum.min(lengths)
      """

      result = fix(code)
      assert result =~ "Enum.min(lengths, fn -> 0 end)"
      refute result =~ "if"
    end

    test "rewrites if var == [] then default else Enum.max(var) to Enum.max/2" do
      code = """
      if lengths == [], do: -1, else: Enum.max(lengths)
      """

      result = fix(code)
      assert result =~ "Enum.max(lengths, fn -> -1 end)"
      refute result =~ "if"
    end

    test "rewrites if var != [] then Enum.min(var) else default" do
      code = """
      if lengths != [], do: Enum.min(lengths), else: 0
      """

      result = fix(code)
      assert result =~ "Enum.min(lengths, fn -> 0 end)"
      refute result =~ "if"
    end

    test "does not modify unrelated code" do
      code = """
      Enum.min(lengths)
      """

      result = fix(code)
      assert result =~ "Enum.min(lengths)"
      refute result =~ "fn ->"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      if lengths == [], do: 0, else: Enum.min(lengths)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoIfEmptyForEnumMinMax.check(ast, []) == []
    end

    test "rewrites case [] -> -1; v -> Enum.max(v) to Enum.max/2" do
      code = """
      case lengths do
        [] -> -1
        filtered -> Enum.max(filtered)
      end
      """

      result = fix(code)
      assert result =~ "Enum.max(lengths, fn -> -1 end)"
      refute result =~ "case"
    end

    test "rewrites case [] -> 0; v -> Enum.min(v) to Enum.min/2" do
      code = """
      case lengths do
        [] -> 0
        filtered -> Enum.min(filtered)
      end
      """

      result = fix(code)
      assert result =~ "Enum.min(lengths, fn -> 0 end)"
      refute result =~ "case"
    end

    test "round-trip: fixed case code produces no issues" do
      code = """
      case lengths do
        [] -> -1
        filtered -> Enum.max(filtered)
      end
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoIfEmptyForEnumMinMax.check(ast, []) == []
    end
  end
end
