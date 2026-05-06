defmodule Credence.Pattern.NoExplicitMinReduceTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoExplicitMinReduce.check(ast, [])
  end

  defp fix(code), do: Credence.Pattern.NoExplicitMinReduce.fix(code, [])

  describe "fixable?" do
    test "reports as fixable" do
      assert Credence.Pattern.NoExplicitMinReduce.fixable?() == true
    end
  end

  describe "NoExplicitMinReduce" do
    test "passes code that uses Enum.min/1 instead of reduce" do
      code = """
      defmodule Goodmin do
        def min_value(list) do
          Enum.min(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses Enum.min_by/2" do
      code = """
      defmodule GoodminBy do
        def min_by_value(list) do
          Enum.min_by(list, & &1)
        end
      end
      """

      assert check(code) == []
    end

    test "detects explicit min/2 inside reduce" do
      code = """
      defmodule BadminReduce do
        def min_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            min(x, acc)
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)

      assert %Issue{} = issue
      assert issue.rule == :no_explicit_min_reduce

      assert issue.message =~ "min-reduction"
      assert issue.meta.line != nil
    end

    test "detects if x < acc pattern inside reduce" do
      code = """
      defmodule BadIfGreater do
        def min_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if x < acc do x else acc end
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_explicit_min_reduce
    end

    test "detects if x <= acc pattern inside reduce" do
      code = """
      defmodule BadIfGreaterEqual do
        def min_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if x <= acc do x else acc end
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end

    test "does NOT detect sum reduction (must avoid false positives)" do
      code = """
      defmodule GoodSum do
        def sum(list) do
          Enum.reduce(list, 0, fn x, acc ->
            acc + x
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect map-based reductions" do
      code = """
      defmodule GoodMapReduce do
        def build_map(list) do
          Enum.reduce(list, %{}, fn x, acc ->
            Map.put(acc, x, true)
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect tuple-based state reducers" do
      code = """
      defmodule GoodStatefulReduce do
        def track(list) do
          Enum.reduce(list, {0, 0}, fn x, {a, b} ->
            {a + x, b}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects multiple explicit min calls inside separate reduces" do
      code = """
      defmodule MultipleBadmin do
        def process(a, b) do
          x = Enum.reduce(a, 0, fn v, acc -> min(v, acc) end)
          y = Enum.reduce(b, 0, fn v, acc -> min(v, acc) end)
          {x, y}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end

    test "ignores unrelated comparison operators outside reduce" do
      code = """
      defmodule NoReduce do
        def compare(a, b) do
          if a > b do
            a
          else
            b
          end
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces min/2 reduce with Enum.min/1" do
      code = """
      Enum.reduce(list, :infinity, fn x, acc -> min(x, acc) end)
      """

      result = fix(code)
      assert result =~ "Enum.min(list)"
      refute result =~ "Enum.reduce"
    end

    test "replaces if < reduce with Enum.min/1" do
      code = """
      Enum.reduce(list, :infinity, fn x, acc ->
        if x < acc do x else acc end
      end)
      """

      result = fix(code)
      assert result =~ "Enum.min(list)"
      refute result =~ "Enum.reduce"
    end

    test "does not modify non-min reductions" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> acc + x end)
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      refute result =~ "Enum.min"
    end

    test "fixes multiple min reduces in one pass" do
      code = """
      defmodule M do
        def run(a, b) do
          x = Enum.reduce(a, :infinity, fn v, acc -> min(v, acc) end)
          y = Enum.reduce(b, :infinity, fn v, acc -> min(v, acc) end)
          {x, y}
        end
      end
      """

      result = fix(code)
      assert result =~ "Enum.min(a)"
      assert result =~ "Enum.min(b)"
      refute result =~ "Enum.reduce"
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(list, :infinity, fn x, acc -> min(x, acc) end)
      """

      fixed = fix(code)
      {:ok, ast} = Code.string_to_quoted(fixed)
      assert Credence.Pattern.NoExplicitMinReduce.check(ast, []) == []
    end
  end
end
