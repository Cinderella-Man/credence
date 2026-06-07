defmodule Credence.Syntax.FixPythonAugmentedAssignmentTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Syntax.FixPythonAugmentedAssignment

  defp analyze(code), do: FixPythonAugmentedAssignment.analyze(code)
  defp fix(code), do: FixPythonAugmentedAssignment.fix(code)

  describe "analyze/1 — flags bare-variable augmented assignment" do
    test "detects += on a simple variable" do
      source = """
      defmodule Example do
        def run(count) do
          count += 1
        end
      end
      """

      issues = analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :python_augmented_assignment
      assert hd(issues).meta.line == 3
    end

    test "detects += with a complex right-hand side" do
      source = """
      defp count_prefix_sums(prefix_counts, current_sum, count, [head | tail], goal) do
        count += Map.get(prefix_counts, new_sum - goal, 0)
      end
      """

      assert length(analyze(source)) == 1
    end

    test "detects -=" do
      assert length(
               analyze("""
               value -= delta
               """)
             ) == 1
    end

    test "detects *=" do
      assert length(
               analyze("""
               total *= factor
               """)
             ) == 1
    end

    test "detects /=" do
      assert length(
               analyze("""
               value /= divisor
               """)
             ) == 1
    end

    test "detects multiple augmented assignments across lines" do
      source = """
      defmodule Example do
        def run(a, b) do
          a += 1
          b -= 2
        end
      end
      """

      assert length(analyze(source)) == 2
    end
  end

  describe "analyze/1 — does NOT flag (safety choices locked in)" do
    test "comment lines" do
      source = """
      defmodule Example do
        # x += 1 is Python syntax
        def run(x), do: x
      end
      """

      assert analyze(source) == []
    end

    test "code without augmented assignment" do
      assert analyze("""
             y = x + 1
             """) == []
    end

    test "operator inside a string literal" do
      assert analyze("""
             x = "a += b"
             """) == []

      assert analyze("""
             msg = "5/=2 ratio"
             """) == []
    end

    test "qualified (dotted) left-hand side — cannot be rebound" do
      assert analyze("""
             socket.assigns.count += 1
             """) == []
    end

    test "indexed left-hand side — not a bare variable" do
      assert analyze("""
             arr[i] += 1
             """) == []
    end

    test "augmented op that is not the leading statement" do
      assert analyze("""
             z = a += b
             """) == []
    end

    test "no right-hand side" do
      assert analyze("""
             x += 
             """) == []
    end
  end

  describe "fix/1 — bare-variable rewrites (RHS parenthesised)" do
    test "fixes += with simple variable" do
      assert fix("""
             count += 1
             """) == """
             count = count + (1)
             """
    end

    test "fixes += with no surrounding spaces" do
      assert fix("""
             x+=1
             """) == """
             x = x + (1)
             """
    end

    test "fixes += with a complex right-hand side" do
      assert fix("""
             count += Map.get(prefix_counts, new_sum - goal, 0)
             """) ==
               """
               count = count + (Map.get(prefix_counts, new_sum - goal, 0))
               """
    end

    test "fixes -= with simple variable" do
      assert fix("""
             value -= delta
             """) == """
             value = value - (delta)
             """
    end

    test "fixes *= with simple variable" do
      assert fix("""
             total *= factor
             """) == """
             total = total * (factor)
             """
    end

    test "fixes /= with simple variable" do
      assert fix("""
             value /= divisor
             """) == """
             value = value / (divisor)
             """
    end

    test "preserves leading indentation" do
      assert fix("""
                 count += 1
             """) == """
                 count = count + (1)
             """
    end

    test "fixes multiple augmented assignments across lines" do
      source = """
      a += 1
      b -= 2
      """

      expected = """
      a = a + (1)
      b = b - (2)
      """

      assert fix(source) == expected
    end

    test "the exact pattern from the row log" do
      source = """
      defp count_prefix_sums(prefix_counts, current_sum, count, [head | tail], goal) do
        new_sum = current_sum + head
        count += Map.get(prefix_counts, new_sum - goal, 0)
        count_prefix_sums(prefix_counts, new_sum, count, tail, goal)
      end
      """

      expected = """
      defp count_prefix_sums(prefix_counts, current_sum, count, [head | tail], goal) do
        new_sum = current_sum + head
        count = count + (Map.get(prefix_counts, new_sum - goal, 0))
        count_prefix_sums(prefix_counts, new_sum, count, tail, goal)
      end
      """

      assert fix(source) == expected
    end
  end

  describe "fix/1 — parenthesising keeps Python operator precedence" do
    # Python `x *= 3 + 4` means `x = x * (3 + 4)` (== 14), NOT `x = x * 3 + 4`
    # (== 10). The naive unparenthesised rewrite would change the answer.
    test "*= with a lower-precedence right-hand side" do
      assert fix("""
             x *= 3 + 4
             """) == """
             x = x * (3 + 4)
             """
    end

    test "-= with a subtraction right-hand side" do
      assert fix("""
             x -= 3 - 1
             """) == """
             x = x - (3 - 1)
             """
    end

    test "/= with a lower-precedence right-hand side" do
      assert fix("""
             x /= a + b
             """) == """
             x = x / (a + b)
             """
    end

    test "-= with a negative literal" do
      assert fix("""
             x -= -1
             """) == """
             x = x - (-1)
             """
    end
  end

  describe "fix/1 — no-ops (must not corrupt valid code)" do
    test "comment line unchanged" do
      code = """
      # x += 1 is Python

      """

      assert fix(code) == code
    end

    test "code without augmented assignment unchanged" do
      code = """
      y = x + 1

      """

      assert fix(code) == code
    end

    test "operator inside a string literal unchanged" do
      code = """
      x = "a += b"
      """

      assert fix(code) == code
    end

    test "string literal containing /= unchanged" do
      code = """
      msg = "5/=2 ratio"
      """

      assert fix(code) == code
    end

    test "qualified left-hand side unchanged" do
      code = """
      socket.assigns.count += 1
      """

      assert fix(code) == code
    end

    test "indexed left-hand side unchanged" do
      code = """
      arr[i] += 1
      """

      assert fix(code) == code
    end

    test "augmented op not leading the statement unchanged" do
      code = """
      z = a += b
      """

      assert fix(code) == code
    end
  end

  describe "round-trip" do
    test "fixed code parses and produces zero analyze issues" do
      code = """
      defmodule Example do
        def run(count) do
          count += 1
          count *= 3 + 4
        end
      end
      """

      fixed = fix(code)
      assert valid_syntax?(fixed)
      assert analyze(fixed) == []
    end
  end
end
