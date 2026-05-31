defmodule Credence.Pattern.NoCaptureFnApplyTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoCaptureFnApply

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCaptureFnApply.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoCaptureFnApply, code)
  end

  describe "NoCaptureFnApply" do
    test "passes normal function calls" do
      code = """
      defmodule Good do
        def process(el, col) do
          Enum.at(el, col)
        end
      end
      """

      assert check(code) == []
    end

    test "passes anonymous function application" do
      code = """
      defmodule Good do
        def process(x) do
          fun = fn y -> y * 2 end
          fun.(x)
        end
      end
      """

      assert check(code) == []
    end

    test "passes function reference capture applied" do
      code = """
      defmodule Good do
        def process(list) do
          (&Enum.map/2).(list, &(&1 + 1))
        end
      end
      """

      assert check(code) == []
    end

    test "detects capture with &1 placeholder applied" do
      code = """
      defmodule Bad do
        def column_sum(matrix, col) do
          Enum.reduce(matrix, 0, fn el, acc -> acc + (&Enum.at(&1, col)).(el) end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_capture_fn_apply
      assert issue.message =~ "Inline the arguments"
      assert issue.meta.line != nil
    end

    test "detects capture with &1 in arithmetic" do
      code = """
      defmodule Bad do
        def double(x) do
          (& &1 * 2).(x)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects multiple capture applications" do
      code = """
      defmodule Bad do
        def process(a, b) do
          x = (& &1 + 1).(a)
          y = (& &1 * 2).(b)
          x + y
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "fixes capture with &1 placeholder" do
      before = """
      defmodule Bad do
        def column_sum(matrix, col) do
          Enum.reduce(matrix, 0, fn el, acc -> acc + (&Enum.at(&1, col)).(el) end)
        end
      end
      """

      after_ = fix(before)
      assert after_ =~ "Enum.at(el, col)"
      refute after_ =~ "(&Enum.at(&1, col)).(el)"
    end

    test "fixes capture with &1 in arithmetic" do
      before = """
      defmodule Bad do
        def double(x) do
          (& &1 * 2).(x)
        end
      end
      """

      after_ = fix(before)
      assert after_ =~ "x * 2"
      refute after_ =~ "(& &1 * 2).(x)"
    end
  end
end
