defmodule Credence.Pattern.NoMinMaxReduceWithIndexTest do
  use ExUnit.Case

  alias Credence.Pattern.NoMinMaxReduceWithIndex

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoMinMaxReduceWithIndex.check(ast, [])
  end

  describe "fires on min/max with index reduce" do
    test "detects min-tracking with index in reduce" do
      code = """
      defmodule BadMinWithIndex do
        def smallest_index(list) do
          [head | _] = list

          list
          |> Stream.with_index()
          |> Enum.reduce({head, 0}, fn {elem, idx}, {min_val, min_idx} ->
            if elem < min_val do
              {elem, idx}
            else
              {min_val, min_idx}
            end
          end)
          |> elem(1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_min_max_reduce_with_index
      assert hd(issues).message =~ "min_by"
    end

    test "detects min-tracking with <= comparison" do
      code = """
      defmodule BadMinEqual do
        def run(list) do
          Enum.reduce(list, {0, 0}, fn {e, i}, {m, mi} ->
            if e <= m do
              {e, i}
            else
              {m, mi}
            end
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects max-tracking with > comparison" do
      code = """
      defmodule BadMaxWithIndex do
        def run(list) do
          Enum.reduce(list, {0, 0}, fn {e, i}, {m, mi} ->
            if e > m do
              {e, i}
            else
              {m, mi}
            end
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects max-tracking with >= comparison" do
      code = """
      defmodule BadMaxEqual do
        def run(list) do
          Enum.reduce(list, {0, 0}, fn {e, i}, {m, mi} ->
            if e >= m do
              {e, i}
            else
              {m, mi}
            end
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "detects reversed comparison (acc < elem)" do
      code = """
      defmodule BadReversed do
        def run(list) do
          Enum.reduce(list, {0, 0}, fn {e, i}, {m, mi} ->
            if m < e do
              {e, i}
            else
              {m, mi}
            end
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "reports correct line number" do
      code = """
      defmodule BadLine do
        def run(list) do
          Enum.reduce(list, {0, 0}, fn {e, i}, {m, mi} ->
            if e < m do
              {e, i}
            else
              {m, mi}
            end
          end)
        end
      end
      """

      issues = check(code)
      assert hd(issues).meta.line != nil
    end

    test "detects multiple independent occurrences" do
      code = """
      defmodule BadMultiple do
        def run(a, b) do
          x =
            Enum.reduce(a, {0, 0}, fn {e, i}, {m, mi} ->
              if e < m, do: {e, i}, else: {m, mi}
            end)

          y =
            Enum.reduce(b, {0, 0}, fn {e, i}, {m, mi} ->
              if e > m, do: {e, i}, else: {m, mi}
            end)

          {x, y}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end
  end

  describe "does not fire on non-matching patterns" do
    test "passes code that uses Enum.min_by/2" do
      code = """
      defmodule GoodMinBy do
        def smallest_index(list) do
          list
          |> Enum.with_index()
          |> Enum.min_by(fn {x, _} -> x end)
          |> elem(1)
        end
      end
      """

      assert check(code) == []
    end

    test "passes code that uses Enum.min/1 (scalar accumulator)" do
      code = """
      defmodule GoodMin do
        def min_value(list) do
          Enum.reduce(list, :infinity, fn x, acc -> min(x, acc) end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes sum reduce" do
      code = """
      defmodule GoodSum do
        def sum(list) do
          Enum.reduce(list, 0, fn x, acc -> x + acc end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes reduce with tuple acc but no if/comparison" do
      code = """
      defmodule GoodTupleNoIf do
        def process(list) do
          Enum.reduce(list, {0, 0}, fn x, {sum, count} ->
            {sum + x, count + 1}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes comparison within same param tuple" do
      code = """
      defmodule GoodSameTuple do
        def run(list) do
          Enum.reduce(list, {0, 0}, fn {x, y}, {sum, count} ->
            if x < y do
              {x, y}
            else
              {sum, count}
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes reduce with non-variable branch expressions" do
      code = """
      defmodule GoodComplexBranches do
        def run(list) do
          Enum.reduce(list, {0, 0}, fn {x, _}, {min_x, count} ->
            if x < min_x do
              {x, count + 1}
            else
              {min_x, count}
            end
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes reduce with single-value accumulator and if/comparison" do
      code = """
      defmodule GoodScalarIf do
        def run(list) do
          Enum.reduce(list, 0, fn x, acc ->
            if x < acc, do: x, else: acc
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes reduce with map accumulator" do
      code = """
      defmodule GoodMapAcc do
        def build(list) do
          Enum.reduce(list, %{}, fn {k, v}, acc ->
            if v > 0, do: Map.put(acc, k, v), else: acc
          end)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "returns empty list (check-only rule)" do
      code = """
      Enum.reduce(list, {0, 0}, fn {e, i}, {m, mi} ->
        if e < m, do: {e, i}, else: {m, mi}
      end)
      """

      ast = Sourceror.parse_string!(code)
      assert NoMinMaxReduceWithIndex.fix_patches(ast, []) == []
    end
  end
end
