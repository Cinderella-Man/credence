defmodule Credence.Rule.NoManualMinTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoManualMin.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoManualMin.fix(code, [])
  end

  describe "NoManualMin" do
    test "detects if a < b, do: a, else: b" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if a < b, do: a, else: b
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_min
      assert issue.message =~ "min/2"
    end

    test "detects if a <= b, do: a, else: b" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if a <= b, do: a, else: b
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "min/2"
    end

    test "detects if b > a, do: a, else: b (flipped comparison)" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if b > a, do: a, else: b
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "min/2"
    end

    test "detects if b >= a, do: a, else: b (flipped with >=)" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if b >= a, do: a, else: b
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "min/2"
    end

    test "detects if a > b, do: b, else: a" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if a > b, do: b, else: a
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "min/2"
    end

    test "detects complex expressions (not just variables)" do
      code = """
      defmodule Bad do
        def clamp_low(value, floor) do
          if value - 1 < floor, do: value - 1, else: floor
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "min/2"
    end

    test "detects with do/end block syntax" do
      code = """
      defmodule Bad do
        def smaller(a, b) do
          if a < b do
            a
          else
            b
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "min/2"
    end

    test "detects multiple instances in one module" do
      code = """
      defmodule Bad do
        def f(a, b, c) do
          x = if a < b, do: a, else: b
          y = if c > x, do: x, else: c
          y
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "does not flag min/2 usage (already correct)" do
      code = """
      defmodule Good do
        def smaller(a, b), do: min(a, b)
      end
      """

      assert check(code) == []
    end

    test "does not flag max pattern (different rule)" do
      code = """
      defmodule Good do
        def bigger(a, b) do
          if a > b, do: a, else: b
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag if with non-comparison condition" do
      code = """
      defmodule Good do
        def pick(flag, a, b) do
          if flag, do: a, else: b
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag if with mismatched branches" do
      code = """
      defmodule Good do
        def transform(a, b) do
          if a < b, do: a * 2, else: b
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag if without else" do
      code = """
      defmodule Good do
        def maybe(a, b) do
          if a < b, do: a
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag if where branches are swapped (would be max)" do
      code = """
      defmodule Good do
        def bigger(a, b) do
          if a < b, do: b, else: a
        end
      end
      """

      assert check(code) == []
    end

    test "fix: if a < b, do: a, else: b → min(a, b)" do
      code = """
      defmodule Example do
        def smaller(a, b), do: if(a < b, do: a, else: b)
      end
      """

      result = fix(code)
      assert result =~ "min(a, b)"
      refute result =~ "if"
    end

    test "fix: if a <= b, do: a, else: b → min(a, b)" do
      code = """
      defmodule Example do
        def smaller(a, b), do: if(a <= b, do: a, else: b)
      end
      """

      result = fix(code)
      assert result =~ "min(a, b)"
      refute result =~ "if"
    end

    test "fix: if b > a, do: a, else: b → min(a, b)" do
      code = """
      defmodule Example do
        def smaller(a, b), do: if(b > a, do: a, else: b)
      end
      """

      result = fix(code)
      assert result =~ "min(a, b)"
      refute result =~ "if"
    end

    test "fix: if b >= a, do: a, else: b → min(a, b)" do
      code = """
      defmodule Example do
        def smaller(a, b), do: if(b >= a, do: a, else: b)
      end
      """

      result = fix(code)
      assert result =~ "min(a, b)"
      refute result =~ "if"
    end

    test "fix: if a > b, do: b, else: a → min(b, a)" do
      code = """
      defmodule Example do
        def smaller(a, b), do: if(a > b, do: b, else: a)
      end
      """

      result = fix(code)
      assert result =~ "min(b, a)"
      refute result =~ "if"
    end

    test "fix: with do/end block syntax" do
      code = """
      defmodule Example do
        def smaller(a, b) do
          if a < b do
            a
          else
            b
          end
        end
      end
      """

      result = fix(code)
      assert result =~ "min(a, b)"
      refute result =~ "if"
    end

    test "fix: complex expressions" do
      code = """
      defmodule Example do
        def clamp_low(value, floor) do
          if value - 1 < floor, do: value - 1, else: floor
        end
      end
      """

      result = fix(code)
      assert result =~ "min("
      assert result =~ "floor)"
      refute result =~ "if"
    end

    test "fix: multiple instances in one module" do
      code = """
      defmodule Example do
        def f(a, b, c) do
          x = if a < b, do: a, else: b
          y = if c > x, do: x, else: c
          y
        end
      end
      """

      result = fix(code)
      refute result =~ "if"
    end

    test "fix: in assignment context" do
      code = """
      defmodule Example do
        def smaller(a, b) do
          result = if a < b, do: a, else: b
          result
        end
      end
      """

      result = fix(code)
      assert result =~ "min(a, b)"
      refute result =~ "if"
    end

    test "fix: inside function call argument" do
      code = """
      defmodule Example do
        def run(a, b) do
          IO.puts(if a < b, do: a, else: b)
        end
      end
      """

      result = fix(code)
      assert result =~ "min(a, b)"
      refute result =~ "if"
    end

    test "fix: does not modify already correct code" do
      code = """
      defmodule Good do
        def smaller(a, b), do: min(a, b)
      end
      """

      result = fix(code)
      assert result =~ "min(a, b)"
      refute result =~ "if"
    end

    test "fix: does not modify max pattern" do
      code = """
      defmodule Good do
        def bigger(a, b) do
          if a > b, do: a, else: b
        end
      end
      """

      result = fix(code)
      assert result =~ "if"
    end

    test "fix: does not modify if with non-comparison condition" do
      code = """
      defmodule Good do
        def pick(flag, a, b) do
          if flag, do: a, else: b
        end
      end
      """

      result = fix(code)
      assert result =~ "if"
    end

    test "fix: does not modify if without else" do
      code = """
      defmodule Good do
        def maybe(a, b) do
          if a < b, do: a
        end
      end
      """

      result = fix(code)
      assert result =~ "if"
    end

    test "fix: does not modify if with mismatched branches" do
      code = """
      defmodule Good do
        def transform(a, b) do
          if a < b, do: a * 2, else: b
        end
      end
      """

      result = fix(code)
      assert result =~ "if"
    end

    test "fix: produces valid Elixir code for simple case" do
      code = """
      defmodule Example do
        def smaller(a, b), do: if(a < b, do: a, else: b)
      end
      """

      result = fix(code)
      assert {:ok, _} = Code.string_to_quoted(result)
    end

    test "fix: produces valid Elixir code for complex expression" do
      code = """
      defmodule Example do
        def clamp_low(value, floor) do
          if value - 1 < floor, do: value - 1, else: floor
        end
      end
      """

      result = fix(code)
      assert {:ok, _} = Code.string_to_quoted(result)
    end
  end
end
