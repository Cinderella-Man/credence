defmodule Credence.Pattern.NoRedundantAssignmentFixTest do
  use ExUnit.Case

  defp fix(code) do
    result = Credence.Pattern.NoRedundantAssignment.fix(code, [])
    if String.ends_with?(result, "\n"), do: result, else: result <> "\n"
  end

  # ═══════════════════════════════════════════════════════════════════
  # TIER 1 — simple variable
  # ═══════════════════════════════════════════════════════════════════

  describe "removes simple variable assign-and-return" do
    test "basic case" do
      input = """
      def run(list) do
        result = Enum.sum(list)
        result
      end
      """

      expected = """
      def run(list) do
        Enum.sum(list)
      end
      """

      assert fix(input) == expected
    end

    test "function call RHS" do
      input = """
      def run(x) do
        output = compute(x)
        output
      end
      """

      expected = """
      def run(x) do
        compute(x)
      end
      """

      assert fix(input) == expected
    end

    test "pipe chain" do
      input = """
      def run(list) do
        output = list |> Enum.map(&process/1) |> Enum.filter(&valid?/1)
        output
      end
      """

      expected = """
      def run(list) do
        list |> Enum.map(&process/1) |> Enum.filter(&valid?/1)
      end
      """

      assert fix(input) == expected
    end

    test "preserves preceding statements" do
      input = """
      def run(list) do
        sorted = Enum.sort(list)
        last = Enum.at(sorted, -1)
        last
      end
      """

      expected = """
      def run(list) do
        sorted = Enum.sort(list)
        Enum.at(sorted, -1)
      end
      """

      assert fix(input) == expected
    end

    test "last pair of multiple rebindings" do
      input = """
      def run(x) do
        result = step1(x)
        result = step2(result)
        result = step3(result)
        result
      end
      """

      expected = """
      def run(x) do
        result = step1(x)
        result = step2(result)
        step3(result)
      end
      """

      assert fix(input) == expected
    end

    test "RHS references the same variable" do
      input = """
      def run(list) do
        list = Enum.reverse(list)
        list
      end
      """

      expected = """
      def run(list) do
        Enum.reverse(list)
      end
      """

      assert fix(input) == expected
    end

    test "inside a module" do
      input = """
      defmodule Example do
        def run(list) do
          last = Enum.at(list, -1)
          last
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          Enum.at(list, -1)
        end
      end
      """

      assert fix(input) == expected
    end

    test "inside a case arm" do
      input = """
      def run(x) do
        case x do
          :compute ->
            result = expensive()
            result

          :default ->
            0
        end
      end
      """

      expected = """
      def run(x) do
        case x do
          :compute ->
            expensive()

          :default ->
            0
        end
      end
      """

      assert fix(input) == expected
    end

    test "inside an if branch" do
      input = """
      def run(x) do
        if x > 0 do
          val = compute(x)
          val
        else
          0
        end
      end
      """

      expected = """
      def run(x) do
        if x > 0 do
          compute(x)
        else
          0
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # TIER 2 — tuple/list of plain variables
  # ═══════════════════════════════════════════════════════════════════

  describe "removes tuple pattern assign-and-return" do
    test "two-element tuple" do
      input = """
      def run(input) do
        {a, b} = process(input)
        {a, b}
      end
      """

      expected = """
      def run(input) do
        process(input)
      end
      """

      assert fix(input) == expected
    end

    test "three-element tuple" do
      input = """
      def run(input) do
        {x, y, z} = compute(input)
        {x, y, z}
      end
      """

      expected = """
      def run(input) do
        compute(input)
      end
      """

      assert fix(input) == expected
    end
  end

  describe "removes list pattern assign-and-return" do
    test "head-tail cons pattern" do
      input = """
      def run(list) do
        [h | t] = list
        [h | t]
      end
      """

      expected = """
      def run(list) do
        list
      end
      """

      assert fix(input) == expected
    end

    test "flat list of variables" do
      input = """
      def run(input) do
        [a, b] = process(input)
        [a, b]
      end
      """

      expected = """
      def run(input) do
        process(input)
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MULTIPLE OCCURRENCES — fixes all blocks independently
  # ═══════════════════════════════════════════════════════════════════

  describe "fixes multiple occurrences" do
    test "both case arms fixed" do
      input = """
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

      expected = """
      def run(x) do
        case x do
          :a ->
            compute_a()

          :b ->
            compute_b()
        end
      end
      """

      assert fix(input) == expected
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SAFETY — must NOT modify
  # ═══════════════════════════════════════════════════════════════════

  describe "does not modify patterns with literals" do
    test "tuple with atom literal" do
      input = """
      def run(input) do
        {:ok, result} = fetch(input)
        {:ok, result}
      end
      """

      assert fix(input) == input
    end

    test "tuple with integer literal" do
      input = """
      def run(input) do
        {1, value} = process(input)
        {1, value}
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify map patterns" do
    test "map destructure" do
      input = """
      def run(user) do
        %{name: name} = user
        %{name: name}
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify when return differs from pattern" do
    test "swapped tuple" do
      input = """
      def run(input) do
        {a, b} = process(input)
        {b, a}
      end
      """

      assert fix(input) == input
    end

    test "partial return" do
      input = """
      def run(input) do
        {a, b, c} = process(input)
        {a, b}
      end
      """

      assert fix(input) == input
    end

    test "different variable name" do
      input = """
      def run(x) do
        result = compute(x)
        output
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify when variable used mid-block" do
    test "variable used between assignment and return" do
      input = """
      def run(x) do
        result = compute(x)
        log(result)
        result
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify underscore assignments" do
    test "_ = expr then _" do
      input = """
      def run(x) do
        _ = side_effect(x)
        _
      end
      """

      assert fix(input) == input
    end
  end

  describe "does not modify already-optimal code" do
    test "direct return" do
      input = """
      def run(list) do
        Enum.at(list, -1)
      end
      """

      assert fix(input) == input
    end

    test "no redundant pattern" do
      input = """
      def run(list) do
        sorted = Enum.sort(list)
        Enum.at(sorted, -1)
      end
      """

      assert fix(input) == input
    end

    test "no block at all" do
      input = """
      defmodule M do
        def run(x), do: x * 2
      end
      """

      assert fix(input) == input
    end
  end
end
