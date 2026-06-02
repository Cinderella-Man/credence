defmodule Credence.Pattern.NoManualListDeleteAtTest do
  use ExUnit.Case

  alias Credence.Pattern.NoManualListDeleteAt

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoManualListDeleteAt.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoManualListDeleteAt, code, [])
  end

  describe "check" do
    test "flags Enum.take ++ Enum.drop pattern" do
      code = """
      defmodule M do
        def remove_at(list, index) do
          Enum.take(list, index) ++ Enum.drop(list, index + 1)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_list_delete_at
      assert issue.message =~ "List.delete_at/2"
    end

    test "flags pattern with commutative + in drop" do
      code = """
      defmodule M do
        def remove_at(list, index) do
          Enum.take(list, index) ++ Enum.drop(list, 1 + index)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_list_delete_at
    end

    test "flags pattern inside a pipe callback" do
      code = """
      defmodule M do
        def permutations(list) do
          list
          |> Enum.with_index()
          |> Enum.flat_map(fn {element, index} ->
            remaining = Enum.take(list, index) ++ Enum.drop(list, index + 1)
            [element | remaining]
          end)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_manual_list_delete_at
    end

    test "does not flag List.delete_at usage" do
      code = """
      defmodule M do
        def remove_at(list, index) do
          List.delete_at(list, index)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag different list variables" do
      code = """
      defmodule M do
        def remove_at(list1, list2, index) do
          Enum.take(list1, index) ++ Enum.drop(list2, index + 1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag different index variables" do
      code = """
      defmodule M do
        def remove_at(list, i, j) do
          Enum.take(list, i) ++ Enum.drop(list, j + 1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when offset is not 1" do
      code = """
      defmodule M do
        def remove_two(list, index) do
          Enum.take(list, index) ++ Enum.drop(list, index + 2)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when take and drop are not concatenated" do
      code = """
      defmodule M do
        def split_at(list, index) do
          before = Enum.take(list, index)
          after_ = Enum.drop(list, index + 1)
          {before, after_}
        end
      end
      """

      assert check(code) == []
    end
  end

  describe "fix" do
    test "replaces Enum.take ++ Enum.drop with List.delete_at" do
      code = """
      defmodule M do
        def remove_at(list, index) do
          Enum.take(list, index) ++ Enum.drop(list, index + 1)
        end
      end
      """

      result = fix(code)
      assert result =~ "List.delete_at(list, index)"
      refute result =~ "Enum.take"
      refute result =~ "Enum.drop"
    end

    test "fixes pattern inside a pipe callback" do
      code = """
      defmodule M do
        def permutations(list) do
          list
          |> Enum.with_index()
          |> Enum.flat_map(fn {element, index} ->
            remaining = Enum.take(list, index) ++ Enum.drop(list, index + 1)
            [element | remaining]
          end)
        end
      end
      """

      result = fix(code)
      assert result =~ "remaining = List.delete_at(list, index)"
    end
  end
end
