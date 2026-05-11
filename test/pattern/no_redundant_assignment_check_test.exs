defmodule Credence.Pattern.NoRedundantAssignmentCheckTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoRedundantAssignment.check(ast, [])
  end

  defp flagged?(code), do: check(code) != []
  defp clean?(code), do: check(code) == []

  # ═══════════════════════════════════════════════════════════════════
  # TIER 1 — simple variable
  # ═══════════════════════════════════════════════════════════════════

  describe "flags simple variable assign-and-return" do
    test "basic case" do
      assert flagged?("""
             def run(list) do
               result = Enum.sum(list)
               result
             end
             """)
    end

    test "function call RHS" do
      assert flagged?("""
             def run(x) do
               output = compute(x)
               output
             end
             """)
    end

    test "pipe chain RHS" do
      assert flagged?("""
             def run(list) do
               output = list |> Enum.map(&process/1) |> Enum.filter(&valid?/1)
               output
             end
             """)
    end

    test "if/else assigned then returned" do
      assert flagged?("""
             def run(x) do
               result = if x > 0, do: :positive, else: :non_positive
               result
             end
             """)
    end

    test "case assigned then returned" do
      assert flagged?("""
             def run(x) do
               result = case x do
                 :a -> 1
                 :b -> 2
               end
               result
             end
             """)
    end

    test "inside a module" do
      assert flagged?("""
             defmodule Example do
               def run(list) do
                 last = Enum.at(list, -1)
                 last
               end
             end
             """)
    end

    test "inside a case arm" do
      assert flagged?("""
             def run(x) do
               case x do
                 :compute ->
                   result = expensive()
                   result
                 :default ->
                   0
               end
             end
             """)
    end

    test "inside an if branch" do
      assert flagged?("""
             def run(x) do
               if x > 0 do
                 val = compute(x)
                 val
               else
                 0
               end
             end
             """)
    end

    test "last pair of multiple rebindings" do
      assert flagged?("""
             def run(x) do
               result = step1(x)
               result = step2(result)
               result = step3(result)
               result
             end
             """)
    end

    test "RHS references the same variable (rebinding)" do
      assert flagged?("""
             def run(list) do
               list = Enum.reverse(list)
               list
             end
             """)
    end

    test "arithmetic RHS" do
      assert flagged?("""
             def run(a, b) do
               sum = a + b
               sum
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # TIER 2 — tuple/list of plain variables
  # ═══════════════════════════════════════════════════════════════════

  describe "flags tuple pattern assign-and-return" do
    test "two-element tuple" do
      assert flagged?("""
             def run(input) do
               {a, b} = process(input)
               {a, b}
             end
             """)
    end

    test "three-element tuple" do
      assert flagged?("""
             def run(input) do
               {x, y, z} = compute(input)
               {x, y, z}
             end
             """)
    end
  end

  describe "flags list pattern assign-and-return" do
    test "head-tail cons pattern" do
      assert flagged?("""
             def run(list) do
               [h | t] = list
               [h | t]
             end
             """)
    end

    test "flat list of variables" do
      assert flagged?("""
             def run(input) do
               [a, b] = process(input)
               [a, b]
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — patterns with literals (assertions, not just bindings)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag patterns containing literals" do
    test "tuple with atom literal" do
      assert clean?("""
             def run(input) do
               {:ok, result} = fetch(input)
               {:ok, result}
             end
             """)
    end

    test "tuple with integer literal" do
      assert clean?("""
             def run(input) do
               {1, value} = process(input)
               {1, value}
             end
             """)
    end

    test "list with literal element" do
      assert clean?("""
             def run(input) do
               [:header, data] = parse(input)
               [:header, data]
             end
             """)
    end

    test "pinned variable in pattern" do
      assert clean?("""
             def run(expected, input) do
               ^expected = process(input)
               ^expected
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — map patterns (subset extraction)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag map patterns" do
    test "map destructure reconstructs a subset" do
      assert clean?("""
             def run(user) do
               %{name: name} = user
               %{name: name}
             end
             """)
    end

    test "map with multiple keys" do
      assert clean?("""
             def run(user) do
               %{name: name, age: age} = user
               %{name: name, age: age}
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — return differs from pattern
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when return differs from pattern" do
    test "swapped tuple elements" do
      assert clean?("""
             def run(input) do
               {a, b} = process(input)
               {b, a}
             end
             """)
    end

    test "partial tuple return" do
      assert clean?("""
             def run(input) do
               {a, b, c} = process(input)
               {a, b}
             end
             """)
    end

    test "different variable name" do
      assert clean?("""
             def run(x) do
               result = compute(x)
               output
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — not the last two statements
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag when variable is used between assignment and return" do
    test "variable used mid-block" do
      assert clean?("""
             def run(x) do
               result = compute(x)
               log(result)
               result
             end
             """)
    end

    test "assignment is not second-to-last" do
      assert clean?("""
             def run(x) do
               result = compute(x)
               other = transform(result)
               result
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — underscore and special cases
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag underscore assignments" do
    test "_ = expr then _" do
      assert clean?("""
             def run(x) do
               _ = side_effect(x)
               _
             end
             """)
    end
  end

  describe "does not flag single-statement blocks" do
    test "no assignment at all" do
      assert clean?("""
             def run(x) do
               compute(x)
             end
             """)
    end

    test "only an assignment, no return" do
      assert clean?("""
             def run(x) do
               result = compute(x)
             end
             """)
    end
  end

  describe "does not flag already-optimal code" do
    test "direct return" do
      assert clean?("""
             def run(list) do
               Enum.at(list, -1)
             end
             """)
    end

    test "multiple statements with no redundant pattern" do
      assert clean?("""
             def run(list) do
               sorted = Enum.sort(list)
               Enum.at(sorted, -1)
             end
             """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES
  # ═══════════════════════════════════════════════════════════════════

  describe "flags multiple occurrences in different blocks" do
    test "both case arms have redundant assignment" do
      code = """
      def run(x) do
        case x do
          :a ->
            r = compute_a()
            r
          :b ->
            r = compute_b()
            r
        end
      end
      """

      assert length(check(code)) == 2
    end
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Pattern.NoRedundantAssignment.fixable?() == true
    end
  end
end
