defmodule Credence.Pattern.NoSumByReduceTest do
  use ExUnit.Case

  alias Credence.Pattern.NoSumByReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoSumByReduce.check(ast, [])
  end

  defp fix(code),
    do: Credence.RuleHelpers.apply_rule_fix(NoSumByReduce, code, [])

  describe "check" do
    test "detects acc + transform(elem) in reduce" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc ->
        acc + digit ** 3
      end)
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_sum_by_reduce
    end

    test "detects transform(elem) + acc in reduce" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc ->
        digit ** 3 + acc
      end)
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_sum_by_reduce
    end

    test "detects acc + elem * 2 pattern" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> acc + x * 2 end)
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT detect plain sum (leaves to no_explicit_sum_reduce)" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> acc + x end)
      """

      assert check(code) == []
    end

    test "does NOT detect plain sum reversed (leaves to no_explicit_sum_reduce)" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> x + acc end)
      """

      assert check(code) == []
    end

    test "does NOT detect non-zero initial accumulator" do
      code = """
      Enum.reduce(list, 10, fn x, acc -> acc + x * 2 end)
      """

      assert check(code) == []
    end

    test "does NOT detect non-sum reduce" do
      code = """
      Enum.reduce(list, 1, fn x, acc -> acc * x end)
      """

      assert check(code) == []
    end

    test "does NOT detect map-based reduce" do
      code = """
      Enum.reduce(list, %{}, fn x, acc -> Map.put(acc, x, true) end)
      """

      assert check(code) == []
    end

    test "passes code that uses Enum.sum_by" do
      code = """
      Enum.sum_by(digits, fn digit -> digit ** 3 end)
      """

      assert check(code) == []
    end

    test "detects multi-clause reduce with no-op catch-all" do
      code = """
      Enum.reduce(points, 0, fn
        [a, b], acc -> acc + distance(a, b)
        _, acc -> acc
      end)
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_sum_by_reduce
    end

    test "detects piped multi-clause reduce with no-op catch-all" do
      code = """
      points
      |> Enum.chunk_every(2, 1)
      |> Enum.reduce(0, fn
        [a, b], acc -> acc + distance(a, b)
        _, acc -> acc
      end)
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT detect multi-clause reduce with non-noop catch-all" do
      code = """
      Enum.reduce(points, 0, fn
        [a, b], acc -> acc + distance(a, b)
        x, acc -> Logger.warn(x); acc
      end)
      """

      assert check(code) == []
    end

    test "does NOT detect multi-clause reduce with no sum clause" do
      code = """
      Enum.reduce(points, 0, fn
        [a, b], acc -> acc * distance(a, b)
        _, acc -> acc
      end)
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "rewrites acc + transform to Enum.sum_by" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc -> acc + digit ** 3 end)
      """

      result = fix(code)
      assert result =~ "Enum.sum_by"
      assert result =~ "digit ** 3"
      refute result =~ "Enum.reduce"
    end

    test "rewrites transform + acc to Enum.sum_by" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc -> digit ** 3 + acc end)
      """

      result = fix(code)
      assert result =~ "Enum.sum_by"
      assert result =~ "digit ** 3"
      refute result =~ "Enum.reduce"
    end

    test "does not modify plain sum reduce" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> acc + x end)
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      refute result =~ "Enum.sum_by"
    end

    test "preserves surrounding code" do
      code = """
      defmodule M do
        def sum_of_cubes(digits) do
          Enum.reduce(digits, 0, fn digit, acc -> acc + digit ** 3 end)
        end
      end
      """

      result = fix(code)
      assert result =~ "defmodule M"
      assert result =~ "def sum_of_cubes"
      assert result =~ "Enum.sum_by"
      refute result =~ "Enum.reduce"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(digits, 0, fn digit, acc -> acc + digit ** 3 end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoSumByReduce.check(ast, []) == []
    end

    test "rewrites multi-clause reduce with catch-all to Enum.sum_by" do
      code = """
      Enum.reduce(points, 0, fn
        [a, b], acc -> acc + distance(a, b)
        _, acc -> acc
      end)
      """

      result = fix(code)
      assert result =~ "Enum.sum_by"
      assert result =~ "distance(a, b)"
      assert result =~ "-> 0"
      refute result =~ "Enum.reduce"
    end

    test "rewrites piped multi-clause reduce with catch-all" do
      code = """
      points
      |> Enum.chunk_every(2, 1)
      |> Enum.reduce(0, fn
        [a, b], acc -> acc + distance(a, b)
        _, acc -> acc
      end)
      """

      result = fix(code)
      assert result =~ "Enum.sum_by"
      assert result =~ "distance(a, b)"
      assert result =~ "-> 0"
      refute result =~ "Enum.reduce"
    end

    test "round-trip: multi-clause fixed code produces no issues" do
      code = """
      Enum.reduce(points, 0, fn
        [a, b], acc -> acc + distance(a, b)
        _, acc -> acc
      end)
      """

      fixed = fix(code)
      ast = Sourceror.parse_string!(fixed)
      assert NoSumByReduce.check(ast, []) == []
    end
  end
end
