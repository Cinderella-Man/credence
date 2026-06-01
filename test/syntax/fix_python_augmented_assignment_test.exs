defmodule Credence.Syntax.FixPythonAugmentedAssignmentTest do
  use ExUnit.Case

  alias Credence.Syntax.FixPythonAugmentedAssignment

  describe "analyze/1" do
    test "detects += on a simple variable" do
      source = """
      defmodule Example do
        def run(count) do
          count += 1
        end
      end
      """

      issues = FixPythonAugmentedAssignment.analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :python_augmented_assignment
      assert hd(issues).message =~ "+="
      assert hd(issues).message =~ "var = var +"
    end

    test "detects += with complex right-hand side" do
      source = """
      defp count_prefix_sums(prefix_counts, current_sum, count, [head | tail], goal) do
        new_sum = current_sum + head
        count += Map.get(prefix_counts, new_sum - goal, 0)
      end
      """

      issues = FixPythonAugmentedAssignment.analyze(source)
      assert length(issues) == 1
      assert hd(issues).message =~ "+="
    end

    test "detects -=" do
      source = """
      defmodule Example do
        def step(value) do
          value -= delta
        end
      end
      """

      issues = FixPythonAugmentedAssignment.analyze(source)
      assert length(issues) == 1
      assert hd(issues).message =~ "-="
    end

    test "detects *=" do
      source = """
      defmodule Example do
        def scale(total) do
          total *= factor
        end
      end
      """

      issues = FixPythonAugmentedAssignment.analyze(source)
      assert length(issues) == 1
      assert hd(issues).message =~ "*="
    end

    test "detects /=" do
      source = """
      defmodule Example do
        def divide(value) do
          value /= divisor
        end
      end
      """

      issues = FixPythonAugmentedAssignment.analyze(source)
      assert length(issues) == 1
      assert hd(issues).message =~ "/="
    end

    test "detects multiple augmented assignments" do
      source = """
      defmodule Example do
        def run(a, b) do
          a += 1
          b -= 2
        end
      end
      """

      issues = FixPythonAugmentedAssignment.analyze(source)
      assert length(issues) == 2
    end

    test "does not flag += in comments" do
      source = """
      defmodule Example do
        # x += 1 is Python syntax
        def run(x), do: x
      end
      """

      assert FixPythonAugmentedAssignment.analyze(source) == []
    end

    test "does not flag code without augmented assignment" do
      source = """
      defmodule Example do
        def run(x) do
          y = x + 1
          y
        end
      end
      """

      assert FixPythonAugmentedAssignment.analyze(source) == []
    end

    test "does not flag regular addition followed by match" do
      source = """
      defmodule Example do
        def run(x, y) do
          z = x + y
          z
        end
      end
      """

      assert FixPythonAugmentedAssignment.analyze(source) == []
    end
  end

  describe "fix/1" do
    test "fixes += with simple variable" do
      source = "count += 1\n"
      fixed = FixPythonAugmentedAssignment.fix(source)
      assert fixed =~ "count = count + 1"
      refute fixed =~ "+="
    end

    test "fixes += with complex right-hand side" do
      source = "count += Map.get(prefix_counts, new_sum - goal, 0)\n"
      fixed = FixPythonAugmentedAssignment.fix(source)
      assert fixed =~ "count = count + Map.get(prefix_counts, new_sum - goal, 0)"
      refute fixed =~ "+="
    end

    test "fixes -= with simple variable" do
      source = "value -= delta\n"
      fixed = FixPythonAugmentedAssignment.fix(source)
      assert fixed =~ "value = value - delta"
      refute fixed =~ "-="
    end

    test "fixes *= with simple variable" do
      source = "total *= factor\n"
      fixed = FixPythonAugmentedAssignment.fix(source)
      assert fixed =~ "total = total * factor"
      refute fixed =~ "*="
    end

    test "fixes /= with simple variable" do
      source = "value /= divisor\n"
      fixed = FixPythonAugmentedAssignment.fix(source)
      assert fixed =~ "value = value / divisor"
      refute fixed =~ "/="
    end

    test "fixes multiple augmented assignments" do
      source = """
      a += 1
      b -= 2
      """

      fixed = FixPythonAugmentedAssignment.fix(source)
      assert fixed =~ "a = a + 1"
      assert fixed =~ "b = b - 2"
      refute fixed =~ "+="
      refute fixed =~ "-="
    end

    test "does not modify comments" do
      source = "# x += 1 is Python\n"
      assert FixPythonAugmentedAssignment.fix(source) == source
    end

    test "does not modify code without augmented assignment" do
      source = "y = x + 1\n"
      assert FixPythonAugmentedAssignment.fix(source) == source
    end

    test "fixes the exact pattern from the row log" do
      source = """
      defp count_prefix_sums(prefix_counts, current_sum, count, [head | tail], goal) do
        new_sum = current_sum + head
        count += Map.get(prefix_counts, new_sum - goal, 0)
        new_prefix_counts = Map.update(prefix_counts, new_sum, 1, &(&1 + 1))
        count_prefix_sums(new_prefix_counts, new_sum, count, tail, goal)
      end
      """

      fixed = FixPythonAugmentedAssignment.fix(source)
      assert fixed =~ "count = count + Map.get(prefix_counts, new_sum - goal, 0)"
      refute fixed =~ "+="
    end
  end
end
