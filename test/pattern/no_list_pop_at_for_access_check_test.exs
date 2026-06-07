defmodule Credence.Pattern.NoListPopAtForAccessCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListPopAtForAccess

  describe "check — flagged shapes (have a safe, same-answer fix)" do
    test "flags fully piped List.pop_at(0) |> elem(0) for the head" do
      code = """
      defmodule Bad do
        def pop_head(list) do
          list |> List.pop_at(0) |> elem(0)
        end
      end
      """

      issues = check(NoListPopAtForAccess, code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_list_pop_at_for_access
      assert issue.message =~ "List.first"
    end

    test "flags fully piped List.pop_at(0) |> elem(1) for the rest" do
      code = """
      defmodule Bad do
        def pop_rest(list) do
          list |> List.pop_at(0) |> elem(1)
        end
      end
      """

      issues = check(NoListPopAtForAccess, code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_list_pop_at_for_access
      assert issue.message =~ "List.delete_at"
    end

    test "flags direct pop_at piped into elem(0)" do
      code = """
      defmodule Bad do
        def pop_head(list) do
          List.pop_at(list, 0) |> elem(0)
        end
      end
      """

      issues = check(NoListPopAtForAccess, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_pop_at_for_access
    end

    test "flags nested elem(List.pop_at(x, 0), 1)" do
      code = """
      defmodule Bad do
        def pop_rest(list) do
          elem(List.pop_at(list, 0), 1)
        end
      end
      """

      issues = check(NoListPopAtForAccess, code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_pop_at_for_access
    end

    test "flags nested elem(List.pop_at(x, 0), 0)" do
      code = """
      defmodule Bad do
        def pop_head(list) do
          elem(List.pop_at(list, 0), 0)
        end
      end
      """

      issues = check(NoListPopAtForAccess, code)
      assert length(issues) == 1
      assert hd(issues).message =~ "List.first"
    end
  end

  describe "check — no issue (no safe, same-answer fix)" do
    test "does not flag List.pop_at with a non-zero index" do
      code = """
      defmodule Good do
        def pop(list) do
          list |> List.pop_at(3) |> elem(0)
        end
      end
      """

      assert check(NoListPopAtForAccess, code) == []
    end

    # elem(2) and beyond are out of the {popped, rest} tuple's range — there
    # is no head/rest accessor they correspond to, so they are never flagged.
    test "does not flag elem index outside {popped, rest}" do
      code = """
      defmodule Good do
        def pop(list) do
          list |> List.pop_at(0) |> elem(2)
        end
      end
      """

      assert check(NoListPopAtForAccess, code) == []
    end

    test "does not flag List.pop_at without an elem extraction" do
      code = """
      defmodule Good do
        def pop(list) do
          {head, rest} = List.pop_at(list, 0)
          {head, rest}
        end
      end
      """

      assert check(NoListPopAtForAccess, code) == []
    end

    test "does not flag elem on a non-List.pop_at expression" do
      code = """
      defmodule Good do
        def get(tuple) do
          elem(tuple, 1)
        end
      end
      """

      assert check(NoListPopAtForAccess, code) == []
    end

    test "does not flag direct hd/1 or tl/1" do
      code = """
      defmodule Good do
        def head(list), do: hd(list)
        def tail(list), do: tl(list)
      end
      """

      assert check(NoListPopAtForAccess, code) == []
    end

    test "does not flag pattern matching for head and tail" do
      code = """
      defmodule Good do
        def split([head | tail]) do
          {head, tail}
        end
      end
      """

      assert check(NoListPopAtForAccess, code) == []
    end
  end
end
