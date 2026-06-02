defmodule Credence.Pattern.NoListReplaceAtInRecursionTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListReplaceAtInRecursion

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListReplaceAtInRecursion.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoListReplaceAtInRecursion, code, [])
  end

  describe "detects List.replace_at with dynamic index in recursive functions" do
    test "flags direct List.replace_at in recursive defp" do
      code = """
      defmodule Filler do
        def fill(list, idx, last_idx) when idx > last_idx, do: list

        def fill(list, idx, last_idx) do
          updated = List.replace_at(list, idx, 9)
          fill(updated, idx + 1, last_idx)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_recursion
      assert hd(issues).message =~ "List.replace_at/3"
    end

    test "flags piped List.replace_at in recursive function" do
      code = """
      defmodule Filler do
        def fill(list, idx, last_idx) when idx > last_idx, do: list

        def fill(list, idx, last_idx) do
          list |> List.replace_at(idx, 9) |> fill(idx + 1, last_idx)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_recursion
    end

    test "flags List.replace_at with arithmetic index in recursive function" do
      code = """
      defmodule Updater do
        def update(list, idx) when idx < 0, do: list

        def update(list, idx) do
          List.replace_at(list, idx - 1, 0) |> update(idx - 1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end
  end

  describe "detects List.update_at with dynamic index in recursive functions" do
    test "flags direct List.update_at in recursive defp" do
      code = """
      defmodule Decrementer do
        def decrement(list, idx) when idx < 0, do: list

        def decrement(list, idx) do
          updated = List.update_at(list, idx, &(&1 - 1))
          decrement(updated, idx - 1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_recursion
      assert hd(issues).message =~ "List.update_at/3"
    end

    test "flags piped List.update_at in recursive function" do
      code = """
      defmodule Decrementer do
        def decrement(list, idx) when idx < 0, do: list

        def decrement(list, idx) do
          list |> List.update_at(idx, &(&1 - 1)) |> decrement(idx - 1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_replace_at_in_recursion
    end
  end

  describe "ignores non-recursive functions" do
    test "does not flag non-recursive function with dynamic List.replace_at" do
      code = """
      defmodule Simple do
        def replace(list, idx, val) do
          List.replace_at(list, idx, val)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "ignores safe patterns" do
    test "does not flag List.replace_at with literal integer index in recursion" do
      code = """
      defmodule Safe do
        def walk(list, acc) when list == [], do: acc

        def walk(list, acc) do
          updated = List.replace_at(list, 0, 9)
          walk(tl(updated), acc)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag List.update_at with literal integer index in recursion" do
      code = """
      defmodule Safe do
        def walk(list, acc) when list == [], do: acc

        def walk(list, acc) do
          updated = List.update_at(list, 0, &(&1 + 1))
          walk(tl(updated), acc)
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "check-only: no auto-fix" do
    test "fix returns source unchanged" do
      code = """
      defmodule Filler do
        def fill(list, idx, last_idx) when idx > last_idx, do: list

        def fill(list, idx, last_idx) do
          updated = List.replace_at(list, idx, 9)
          fill(updated, idx + 1, last_idx)
        end
      end
      """

      result = fix(code)
      assert result == code
    end
  end
end
