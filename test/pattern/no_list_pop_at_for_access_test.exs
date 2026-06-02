defmodule Credence.Pattern.NoListPopAtForAccessTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListPopAtForAccess

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoListPopAtForAccess.check(ast, [])
  end

  describe "check" do
    # --- POSITIVE CASES ---

    test "flags piped List.pop_at(0) |> elem(1) for tail" do
      code = """
      defmodule Bad do
        def pop_tail(list) do
          list |> List.pop_at(0) |> elem(1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_list_pop_at_for_access
      assert issue.message =~ "tl/1"
    end

    test "flags piped List.pop_at(0) |> elem(0) for head" do
      code = """
      defmodule Bad do
        def pop_head(list) do
          list |> List.pop_at(0) |> elem(0)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_list_pop_at_for_access
      assert issue.message =~ "hd/1"
    end

    test "flags nested elem(List.pop_at(x, 0), 1)" do
      code = """
      defmodule Bad do
        def pop_tail(list) do
          elem(List.pop_at(list, 0), 1)
        end
      end
      """

      issues = check(code)
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

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_pop_at_for_access
      assert hd(issues).message =~ "hd/1"
    end

    test "flags pattern in function body like the generated code" do
      code = """
      defmodule Solution do
        defp process_char("#", [_ = _previous | _rest] = stack) do
          stack |> List.pop_at(0) |> elem(1)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_pop_at_for_access
    end

    # --- NEGATIVE CASES ---

    test "does not flag List.pop_at with non-zero index" do
      code = """
      defmodule Good do
        def pop(list) do
          list |> List.pop_at(3) |> elem(0)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag List.pop_at without elem" do
      code = """
      defmodule Good do
        def pop(list) do
          {head, rest} = List.pop_at(list, 0)
          {head, rest}
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag elem on non-List.pop_at expression" do
      code = """
      defmodule Good do
        def get(tuple) do
          elem(tuple, 1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag tl/1 directly" do
      code = """
      defmodule Good do
        def tail(list) do
          tl(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag hd/1 directly" do
      code = """
      defmodule Good do
        def head(list) do
          hd(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag pattern matching for head and tail" do
      code = """
      defmodule Good do
        def split([head | tail]) do
          {head, tail}
        end
      end
      """

      assert check(code) == []
    end
  end
end
