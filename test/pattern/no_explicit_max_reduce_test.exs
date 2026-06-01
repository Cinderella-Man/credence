defmodule Credence.Pattern.NoExplicitMaxReduceTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoExplicitMaxReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoExplicitMaxReduce.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoExplicitMaxReduce, code, [])
  end

  describe "NoExplicitMaxReduce" do
    test "passes code that uses Enum.max/1 instead of reduce" do
      code = """
      defmodule GoodMax do
        def max_value(list) do
          Enum.max(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses Enum.max_by/2" do
      code = """
      defmodule GoodMaxBy do
        def max_by_value(list) do
          Enum.max_by(list, & &1)
        end
      end
      """

      assert check(code) == []
    end

    test "detects explicit max/2 inside reduce" do
      code = """
      defmodule BadMaxReduce do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            max(x, acc)
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)

      assert %Issue{} = issue
      assert issue.rule == :no_explicit_max_reduce

      assert issue.message =~ "max-reduction"
      assert issue.meta.line != nil
    end

    test "detects if x > acc pattern inside reduce" do
      code = """
      defmodule BadIfGreater do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if x > acc do x else acc end
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_explicit_max_reduce
    end

    test "detects if x >= acc pattern inside reduce" do
      code = """
      defmodule BadIfGreaterEqual do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if x >= acc do x else acc end
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

    test "detects multiple explicit max calls inside separate reduces" do
      code = """
      defmodule MultipleBadMax do
        def process(a, b) do
          x = Enum.reduce(a, 0, fn v, acc -> max(v, acc) end)
          y = Enum.reduce(b, 0, fn v, acc -> max(v, acc) end)
          {x, y}
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end

    test "detects max-by pattern with same function on both sides" do
      code = """
      defmodule BadMaxByReduce do
        def max_length(strings) do
          Enum.reduce(strings, "", fn str, longest ->
            if String.length(str) > String.length(longest), do: str, else: longest
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_explicit_max_reduce
      assert hd(issues).message =~ "max-by"
    end

    test "detects max-by pattern with >= operator" do
      code = """
      defmodule BadMaxByReduceEq do
        def max_length(strings) do
          Enum.reduce(strings, "", fn str, longest ->
            if String.length(str) >= String.length(longest), do: str, else: longest
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "max-by"
    end

    test "detects max-by with unqualified function calls" do
      code = """
      defmodule BadMaxByUnqual do
        def max_length(lists) do
          Enum.reduce(lists, [], fn sub, longest ->
            if length(sub) > length(longest), do: sub, else: longest
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "does NOT detect max-by with different functions on each side" do
      code = """
      defmodule GoodDiffFns do
        def process(list) do
          Enum.reduce(list, "", fn str, acc ->
            if String.length(str) > byte_size(acc), do: str, else: acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect max-by when one side is not a function call" do
      code = """
      defmodule GoodOneSideVar do
        def process(list) do
          Enum.reduce(list, 0, fn str, acc ->
            if String.length(str) > acc, do: String.length(str), else: acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect max-reduce with transformation (e.g. length)" do
      code = """
      defmodule GoodMaxTransform do
        def max_length(lists) do
          Enum.reduce(lists, 0, fn sub, acc ->
            max(acc, length(sub))
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect if-greater with transformation" do
      code = """
      defmodule GoodIfTransform do
        def max_length(lists) do
          Enum.reduce(lists, 0, fn sub, acc ->
            if length(sub) > acc, do: length(sub), else: acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect if >= returning tuples (stateful reducer)" do
      code = """
      defmodule GoodStatefulIfReduce do
        def process(list) do
          Enum.reduce(list, {0, nil}, fn [entry, exit], {cameras, last_camera} ->
            if last_camera >= entry do
              {cameras, last_camera}
            else
              {cameras + 1, exit}
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does NOT detect if > returning non-compared values" do
      code = """
      defmodule GoodIfNonMax do
        def track(list) do
          Enum.reduce(list, {0, 0}, fn x, {sum, max_val} ->
            if x > max_val do
              {sum + x, x}
            else
              {sum + x, max_val}
            end
          end)
        end
      end
      """

      assert check(code) == []
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

  describe "fix/2" do
    test "replaces max/2 reduce with Enum.max/1" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        max(x, acc)
      end)
      """

      result = fix(code)

      assert result =~ "Enum.max(list)"
      refute result =~ "Enum.reduce"
    end

    test "replaces if > reduce with Enum.max/1" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if x > acc do x else acc end
      end)
      """

      result = fix(code)

      assert result =~ "Enum.max(list)"
      refute result =~ "Enum.reduce"
    end

    test "replaces if >= reduce with Enum.max/1" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if x >= acc do x else acc end
      end)
      """

      result = fix(code)

      assert result =~ "Enum.max(list)"
      refute result =~ "Enum.reduce"
    end

    test "does not modify sum reductions" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        acc + x
      end)
      """

      result = fix(code)

      assert result =~ "Enum.reduce"
      refute result =~ "Enum.max"
    end

    test "fixes multiple max reduces in one pass" do
      code = """
      defmodule MultiFix do
        def process(a, b) do
          x = Enum.reduce(a, 0, fn v, acc -> max(v, acc) end)
          y = Enum.reduce(b, 0, fn v, acc -> max(v, acc) end)
          {x, y}
        end
      end
      """

      result = fix(code)

      assert result =~ "Enum.max(a)"
      assert result =~ "Enum.max(b)"
      refute result =~ "Enum.reduce"
    end

    test "preserves surrounding code when fixing" do
      code = """
      defmodule Preserved do
        def run(list) do
          total = Enum.sum(list)
          biggest = Enum.reduce(list, 0, fn x, acc -> max(x, acc) end)
          {total, biggest}
        end
      end
      """

      result = fix(code)

      assert result =~ "Enum.sum(list)"
      assert result =~ "Enum.max(list)"
      assert result =~ "{total, biggest}"
      refute result =~ "Enum.reduce"
    end

    test "fixed code produces no issues" do
      code = """
      defmodule RoundTrip do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            max(x, acc)
          end)
        end
      end
      """

      fixed = fix(code)
      {:ok, fixed_ast} = Sourceror.parse_string(fixed)
      issues = NoExplicitMaxReduce.check(fixed_ast, [])

      assert issues == []
    end

    test "fix includes variable accumulator via cons (e.g. head | tail pattern)" do
      code = """
      defmodule VarAcc do
        def max_value([head | tail]) do
          Enum.reduce(tail, head, fn item, current_max ->
            if item > current_max, do: item, else: current_max
          end)
        end
      end
      """

      result = fix(code)

      # Must include head in the max — Enum.max([head | tail]), NOT Enum.max(tail)
      assert result =~ "Enum.max([head | tail])"
      refute result =~ "Enum.max(tail)"
      refute result =~ "Enum.reduce"
    end

    test "does not fix max-by pattern (check-only)" do
      code = """
      Enum.reduce(strings, "", fn str, longest ->
        if String.length(str) > String.length(longest), do: str, else: longest
      end)
      """

      result = fix(code)
      assert result =~ "Enum.reduce"
      refute result =~ "Enum.max_by"
    end

    test "fix uses Enum.max(enum) when acc is a literal sentinel" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        if x > acc, do: x, else: acc
      end)
      """

      result = fix(code)

      assert result =~ "Enum.max(list)"
      refute result =~ "Enum.reduce"
    end
  end
end
