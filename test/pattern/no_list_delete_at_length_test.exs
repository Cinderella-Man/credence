defmodule Credence.Pattern.NoListDeleteAtLengthTest do
  use ExUnit.Case

  alias Credence.Pattern.NoListDeleteAtLength

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
      issues = NoListDeleteAtLength.check(ast, [])
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_delete_at_length
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
      issues = NoListDeleteAtLength.check(ast, [])
      assert length(issues) == 1
      assert hd(issues).message =~ "last 2 elements"
    end

    test "does not flag List.delete_at with a literal index" do
      source = """
      defmodule M do
        def drop(list) do
          List.delete_at(list, 0)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtLength.check(ast, [])
      assert issues == []
    end

    test "does not flag List.delete_at with a different variable's length" do
      source = """
      defmodule M do
        def drop(list, other) do
          List.delete_at(list, length(other) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtLength.check(ast, [])
      assert issues == []
    end

    test "does not flag List.delete_at with a variable index" do
      source = """
      defmodule M do
        def drop(list, idx) do
          List.delete_at(list, idx)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtLength.check(ast, [])
      assert issues == []
    end

    test "does not flag Enum.at with length (covered by no_length_based_indexing)" do
      source = """
      defmodule M do
        def get(list) do
          Enum.at(list, length(list) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      issues = NoListDeleteAtLength.check(ast, [])
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
      issues = NoListDeleteAtLength.check(ast, [])
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_delete_at_length
    end
  end

  describe "fix_patches/2" do
    test "returns empty list (check-only rule)" do
      source = """
      defmodule M do
        def drop_last(list) do
          List.delete_at(list, length(list) - 1)
        end
      end
      """

      ast = Sourceror.parse_string!(source)
      assert NoListDeleteAtLength.fix_patches(ast, source: source) == []
    end
  end

  # ── Integration through Credence.Pattern ──────────────────────────

  describe "integration" do
    test "detected through pattern pipeline" do
      source = """
      defmodule IntegDeleteAt do
        def drop_last(list) do
          List.delete_at(list, length(list) - 1)
        end
      end
      """

      issues = Credence.Pattern.analyze(source)
      found = Enum.filter(issues, &(&1.rule == :no_list_delete_at_length))
      assert length(found) == 1
    end

    test "not flagged when index is not length-based" do
      source = """
      defmodule IntegDeleteAtOk do
        def drop_first(list) do
          List.delete_at(list, 0)
        end
      end
      """

      issues = Credence.Pattern.analyze(source)
      found = Enum.filter(issues, &(&1.rule == :no_list_delete_at_length))
      assert found == []
    end
  end
end
