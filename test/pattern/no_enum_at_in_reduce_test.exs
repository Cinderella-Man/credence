defmodule Credence.Pattern.NoEnumAtInReduceTest do
  use ExUnit.Case

  alias Credence.Pattern.NoEnumAtInReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoEnumAtInReduce.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoEnumAtInReduce, code, [])
  end

  describe "detects Enum.at with dynamic index inside reduce callbacks" do
    test "flags Enum.at inside Enum.reduce_while" do
      code = """
      defmodule SlidingWindow do
        def find(nums, k) do
          Enum.reduce_while(Enum.with_index(nums), {false, %{}}, fn {num, i}, {found, window} ->
            left_num = Enum.at(nums, i - k)
            {:cont, {found, Map.put(window, left_num, num)}}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_at_in_reduce
      assert hd(issues).message =~ "List.to_tuple/1"
    end

    test "flags Enum.at inside Enum.reduce" do
      code = """
      defmodule Acc do
        def run(list) do
          Enum.reduce(list, 0, fn x, acc ->
            val = Enum.at(list, x)
            acc + val
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_enum_at_in_reduce
    end

    test "flags Enum.at inside Enum.map" do
      code = """
      defmodule Remap do
        def remap(list) do
          Enum.map(list, fn x ->
            Enum.at(list, x)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags Enum.at inside Enum.each" do
      code = """
      defmodule Printer do
        def print(list) do
          Enum.each(list, fn x ->
            val = Enum.at(list, x)
            IO.puts(val)
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags Enum.at inside Enum.filter" do
      code = """
      defmodule Filt do
        def select(list) do
          Enum.filter(list, fn x ->
            Enum.at(list, x) > 0
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags piped Enum.at inside reduce callback" do
      code = """
      defmodule Piped do
        def run(list) do
          Enum.reduce(list, 0, fn x, acc ->
            val = list |> Enum.at(x)
            acc + val
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    test "flags multiple Enum.at calls in same callback" do
      code = """
      defmodule Multi do
        def run(list) do
          Enum.reduce(list, 0, fn {x, i}, acc ->
            a = Enum.at(list, i)
            b = Enum.at(list, i + 1)
            acc + a + b
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "flags Enum.at with arithmetic index in reduce" do
      code = """
      defmodule Arith do
        def run(nums, k) do
          Enum.reduce_while(Enum.with_index(nums), %{}, fn {num, i}, window ->
            old = Enum.at(nums, i - k)
            {:cont, Map.put(window, old, num)}
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end
  end

  describe "ignores safe patterns" do
    test "does not flag Enum.at with literal integer index" do
      code = """
      defmodule Safe do
        def run(list) do
          Enum.reduce(list, 0, fn x, acc ->
            first = Enum.at(list, 0)
            acc + first
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag code using elem/tuple inside reduce" do
      code = """
      defmodule Fast do
        def run(list, k) do
          tuple = List.to_tuple(list)

          Enum.reduce_while(Enum.with_index(list), %{}, fn {num, i}, window ->
            old = elem(tuple, i - k)
            {:cont, Map.put(window, old, num)}
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.at outside of loop callbacks" do
      code = """
      defmodule Outside do
        def run(list, idx) do
          val = Enum.at(list, idx)
          val + 1
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.at inside a regular function (not a callback)" do
      code = """
      defmodule Helper do
        def get_value(list, idx) do
          Enum.at(list, idx)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "check-only: no auto-fix" do
    test "fix returns source unchanged" do
      code = """
      defmodule Walker do
        def run(list) do
          Enum.reduce(list, 0, fn x, acc ->
            val = Enum.at(list, x)
            acc + val
          end)
        end
      end
      """

      result = fix(code)
      assert result == code
    end
  end
end
