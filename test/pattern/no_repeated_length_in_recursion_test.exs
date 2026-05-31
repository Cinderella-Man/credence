defmodule Credence.Pattern.NoRepeatedLengthInRecursionTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRepeatedLengthInRecursion

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRepeatedLengthInRecursion.check(ast, [])
  end

  describe "NoRepeatedLengthInRecursion" do
    test "detects length(param) inside recursive function with unchanged param" do
      code = """
      defmodule Bad do
        defp sliding_window(charlist, left, right, max_length, seen) do
          if right >= length(charlist) do
            max_length
          else
            sliding_window(charlist, left, right + 1, max_length, seen)
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_repeated_length_in_recursion
      assert issue.message =~ "length(charlist)"
      assert issue.message =~ "recomputed"
    end

    test "detects Enum.count(param) inside recursive function with unchanged param" do
      code = """
      defmodule Bad do
        defp loop(list, i, acc) do
          if i >= Enum.count(list) do
            acc
          else
            loop(list, i + 1, acc + 1)
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_repeated_length_in_recursion
      assert issue.message =~ "length(list)"
    end

    test "detects piped Enum.count(param) inside recursive function" do
      code = """
      defmodule Bad do
        defp loop(list, i) do
          if list |> Enum.count() > i do
            loop(list, i + 1)
          end
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_repeated_length_in_recursion
    end

    test "detects multiple length calls on different unchanged params" do
      code = """
      defmodule Bad do
        defp compare(a, b, i) do
          if i >= length(a) or i >= length(b) do
            :done
          else
            compare(a, b, i + 1)
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    # ---- Negative cases ----

    test "does not flag length(param) in non-recursive function" do
      code = """
      defmodule Good do
        def count(list) do
          length(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag length(param) when param changes in recursive call" do
      code = """
      defmodule Good do
        defp process(list, acc) do
          len = length(list)
          [_ | tail] = list
          process(tail, acc + len)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag length on non-parameter variable" do
      code = """
      defmodule Good do
        defp loop(list, i) do
          subset = Enum.take(list, i)
          if length(subset) > 0 do
            loop(list, i + 1)
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag length in a function with no self-call" do
      code = """
      defmodule Good do
        defp helper(list) do
          n = length(list)
          Enum.map(list, &(&1 + n))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when recursive call passes different arg at length param position" do
      code = """
      defmodule Good do
        defp loop(list, i, acc) do
          if i >= length(list) do
            acc
          else
            new_list = Enum.drop(list, 1)
            loop(new_list, i + 1, acc + 1)
          end
        end
      end
      """

      assert check(code) == []
    end
  end
end
