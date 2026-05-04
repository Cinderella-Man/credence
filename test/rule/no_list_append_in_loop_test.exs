defmodule Credence.Rule.NoListAppendInLoopTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoListAppendInLoop.check(ast, [])
  end

  describe "NoListAppendInLoop - exclusions for fixable rules" do
    test "does not flag fixable acc ++ [expr] in reduce with [] initial" do
      code = """
      defmodule Fixable do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item * 2]
          end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag fixable direct acc ++ [expr] in recursive call" do
      code = """
      defmodule Fixable do
        def build([h | t], result) do
          build(t, result ++ [h * 2])
        end

        def build([], result), do: result
      end
      """

      assert check(code) == []
    end
  end

  describe "NoListAppendInLoop - still flagged cases" do
    test "flags ++ in reduce with non-empty initial accumulator" do
      code = """
      defmodule Bad do
        def process(list) do
          Enum.reduce(list, [0], fn item, acc ->
            acc ++ [item]
          end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_append_in_loop
    end

    test "flags indirect ++ in recursive function (assigned to variable)" do
      code = """
      defmodule BadRecursive do
        defp slide([next | rest], [out | window], current, current_max) do
          new_current = current - out + next
          new_max = max(current_max, new_current)
          new_window = window ++ [next]
          slide(rest, new_window, new_current, new_max)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_append_in_loop
    end

    test "flags ++ inside a for comprehension" do
      code = """
      defmodule BadCodeFor do
        def process(list) do
          for item <- list do
            acc = []
            acc ++ [item]
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_append_in_loop
    end

    test "flags ++ in guarded recursive function with indirect append" do
      code = """
      defmodule Bad do
        defp helper([h | t], acc) when is_integer(h) do
          new_acc = acc ++ [h]
          helper(t, new_acc)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end
  end

  describe "NoListAppendInLoop - negative cases" do
    test "passes idiomatic prepend code" do
      code = """
      defmodule GoodCode do
        def process(list) do
          list
          |> Enum.reduce([], fn item, acc ->
            [item * 2 | acc]
          end)
          |> Enum.reverse()
        end
      end
      """

      assert check(code) == []
    end

    test "ignores ++ outside of a looping construct" do
      code = """
      defmodule SafeAppend do
        def concat(list_a, list_b) do
          list_a ++ list_b
        end
      end
      """

      assert check(code) == []
    end

    test "ignores ++ in a non-recursive function" do
      code = """
      defmodule SafeNonRecursive do
        def prepare(list) do
          prefix = [0]
          prefix ++ list
        end
      end
      """

      assert check(code) == []
    end
  end
end
