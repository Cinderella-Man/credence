defmodule Credence.Rule.NoListAppendInLoopTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoListAppendInLoop.check(ast, [])
  end

  describe "NoListAppendInLoop - Enum.reduce and for" do
    test "passes idiomatic code without issues" do
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

    test "detects ++ inside Enum.reduce" do
      code = """
      defmodule BadCodeReduce do
        def process(list) do
          Enum.reduce(list, [], fn item, acc ->
            acc ++ [item * 2]
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_list_append_in_loop

      assert issue.message =~ "++"
      assert issue.meta.line != nil
    end

    test "detects ++ inside a for comprehension" do
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

    test "ignores ++ if it is outside of a looping construct" do
      code = """
      defmodule SafeAppend do
        def concat(list_a, list_b) do
          list_a ++ list_b
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "NoListAppendInLoop - recursive functions" do
    test "detects ++ inside a recursive defp" do
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
      issue = hd(issues)
      assert issue.rule == :no_list_append_in_loop

      assert issue.meta.line != nil
    end

    test "detects ++ inside a guarded recursive function" do
      code = """
      defmodule BadGuardedRecursive do
        defp helper([h | t], acc) when is_integer(h) do
          helper(t, acc ++ [h])
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_list_append_in_loop
    end

    test "detects ++ inside a recursive def (public function)" do
      code = """
      defmodule BadPublicRecursive do
        def build([h | t], result) do
          build(t, result ++ [h * 2])
        end

        def build([], result), do: result
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).rule == :no_list_append_in_loop
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

    test "ignores non-recursive clause of a multi-clause function" do
      code = """
      defmodule MixedClauses do
        defp slide([], _window, _current, current_max), do: current_max

        defp slide([next | rest], [out | window], current, current_max) do
          new_window = window ++ [next]
          slide(rest, new_window, current, current_max)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
    end
  end
end
