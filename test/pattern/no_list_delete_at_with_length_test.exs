defmodule Credence.Pattern.NoListDeleteAtWithLengthTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListDeleteAtWithLength

  describe "check/2" do
    test "flags List.delete_at(x, length(x) - 1)" do
      source = """
      defmodule M do
        def drop_last(list) do
          List.delete_at(list, length(list) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtWithLength.check(ast, [])
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_delete_at_with_length
      assert hd(issues).message =~ "List.delete_at"
      assert hd(issues).message =~ "Enum.split"
    end

    test "flags List.delete_at(x, length(x) - 2)" do
      source = """
      defmodule M do
        def drop(list) do
          List.delete_at(list, length(list) - 2)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtWithLength.check(ast, [])
      assert length(issues) == 1
      assert hd(issues).message =~ "2"
    end

    test "flags with Kernel.length" do
      source = """
      defmodule M do
        def drop_last(list) do
          List.delete_at(list, Kernel.length(list) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtWithLength.check(ast, [])
      assert length(issues) == 1
    end

    test "does not flag List.delete_at with literal index" do
      source = """
      defmodule M do
        def drop(list) do
          List.delete_at(list, 0)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtWithLength.check(ast, [])
      assert issues == []
    end

    test "does not flag List.delete_at with different variable for length" do
      source = """
      defmodule M do
        def drop(list, other) do
          List.delete_at(list, length(other) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtWithLength.check(ast, [])
      assert issues == []
    end

    test "does not flag List.delete_at with non-literal offset" do
      source = """
      defmodule M do
        def drop(list, n) do
          List.delete_at(list, length(list) - n)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtWithLength.check(ast, [])
      assert issues == []
    end

    test "does not flag Enum.at with length (handled by no_length_based_indexing)" do
      source = """
      defmodule M do
        def get_last(list) do
          Enum.at(list, length(list) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtWithLength.check(ast, [])
      assert issues == []
    end

    test "flags the pattern from the row log" do
      source = """
      defmodule Solution do
        def swap_head_tail(list) do
          [head | tail] = list
          last = List.last(tail)
          middle = List.delete_at(tail, length(tail) - 1)
          [last | middle] ++ [head]
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtWithLength.check(ast, [])
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_delete_at_with_length
    end
  end

  describe "fix_patches/2" do
    test "returns empty list (check-only)" do
      source = """
      defmodule M do
        def drop_last(list) do
          List.delete_at(list, length(list) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      assert NoListDeleteAtWithLength.fix_patches(ast, source: source) == []
    end
  end

  describe "integration through Credence.Pattern" do
    test "detects the anti-pattern via the pipeline" do
      source = """
      defmodule M do
        def drop_last(list) do
          List.delete_at(list, length(list) - 1)
        end
      end
      """

      issues = Credence.Pattern.analyze(source)
      found = Enum.filter(issues, &(&1.rule == :no_list_delete_at_with_length))
      assert length(found) == 1
    end

    test "does not flag when index is not length-based" do
      source = """
      defmodule M do
        def drop_idx(list, idx) do
          List.delete_at(list, idx)
        end
      end
      """

      issues = Credence.Pattern.analyze(source)
      found = Enum.filter(issues, &(&1.rule == :no_list_delete_at_with_length))
      assert found == []
    end
  end
end
