defmodule Credence.Pattern.NoListDeleteAtInLoopTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoListDeleteAtInLoop.check(ast, [])
  end

  describe "NoListDeleteAtInLoop" do
    test "passes code without List.delete_at in loops" do
      code = """
      defmodule Good do
        def process(list) do
          Enum.map(list, &(&1 * 2))
        end
      end
      """

      assert check(code) == []
    end

    test "passes List.delete_at outside of loops" do
      code = """
      defmodule Safe do
        def remove_third(list) do
          List.delete_at(list, 2)
        end
      end
      """

      assert check(code) == []
    end

    test "detects List.delete_at inside for comprehension" do
      code = """
      defmodule BadFor do
        def perms(list) do
          for {elem, idx} <- Enum.with_index(list) do
            rest = List.delete_at(list, idx)
            [elem | rest]
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_list_delete_at_in_loop

      assert issue.message =~ "List.delete_at"
      assert issue.meta.line != nil
    end

    test "detects List.delete_at inside Enum.map" do
      code = """
      defmodule BadMap do
        def remove_each(list) do
          Enum.map(0..(length(list) - 1), fn idx ->
            List.delete_at(list, idx)
          end)
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      assert hd(issues).rule == :no_list_delete_at_in_loop
    end

    test "detects List.delete_at inside recursive function" do
      code = """
      defmodule BadRecursive do
        def perms([], _acc), do: [[]]

        def perms(list, acc) do
          rest = List.delete_at(list, 0)
          perms(rest, [hd(list) | acc])
        end
      end
      """

      issues = check(code)

      assert length(issues) >= 1
      assert hd(issues).rule == :no_list_delete_at_in_loop
    end

    test "ignores List.delete_at in non-recursive function" do
      code = """
      defmodule SafeNonRecursive do
        def remove_first(list) do
          List.delete_at(list, 0)
        end
      end
      """

      assert check(code) == []
    end
  end
end
