defmodule Credence.Pattern.NoListDeleteAtWithLengthCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListDeleteAtWithLength

  describe "flagged shapes" do
    test "flags List.delete_at(x, length(x) - 1)" do
      source = """
      defmodule M do
        def drop_last(list) do
          List.delete_at(list, length(list) - 1)
        end
      end
      """

      issues = check(NoListDeleteAtWithLength, source)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_delete_at_with_length
      assert hd(issues).message =~ "List.delete_at(list, -1)"
    end

    test "flags with Kernel.length" do
      source = """
      defmodule M do
        def drop_last(list) do
          List.delete_at(list, Kernel.length(list) - 1)
        end
      end
      """

      assert length(check(NoListDeleteAtWithLength, source)) == 1
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

      issues = check(NoListDeleteAtWithLength, source)
      assert length(issues) == 1
      assert hd(issues).rule == :no_list_delete_at_with_length
    end
  end

  describe "deliberately dropped shapes (no issue)" do
    # `List.delete_at(x, length(x) - K)` for K >= 2 removes the single
    # element K-from-end, which `List.delete_at(x, -K)` does NOT match when
    # the list is shorter than K (e.g. `[1]`, K=2: original drops the last
    # element -> `[]`, but `-2` is out of range -> `[1]`). No same-answer
    # single-expression rewrite exists, so these are not flagged.
    test "does not flag offset of 2" do
      source = """
      defmodule M do
        def drop(list) do
          List.delete_at(list, length(list) - 2)
        end
      end
      """

      assert check(NoListDeleteAtWithLength, source) == []
    end

    test "does not flag offset of 3" do
      source = """
      defmodule M do
        def drop(list) do
          List.delete_at(list, length(list) - 3)
        end
      end
      """

      assert check(NoListDeleteAtWithLength, source) == []
    end

    test "does not flag List.delete_at with a literal index" do
      source = """
      defmodule M do
        def drop(list) do
          List.delete_at(list, 0)
        end
      end
      """

      assert check(NoListDeleteAtWithLength, source) == []
    end

    test "does not flag when the length variable differs" do
      source = """
      defmodule M do
        def drop(list, other) do
          List.delete_at(list, length(other) - 1)
        end
      end
      """

      assert check(NoListDeleteAtWithLength, source) == []
    end

    test "does not flag a non-literal offset" do
      source = """
      defmodule M do
        def drop(list, n) do
          List.delete_at(list, length(list) - n)
        end
      end
      """

      assert check(NoListDeleteAtWithLength, source) == []
    end

    test "does not flag Enum.at with length (handled by no_length_based_indexing)" do
      source = """
      defmodule M do
        def get_last(list) do
          Enum.at(list, length(list) - 1)
        end
      end
      """

      assert check(NoListDeleteAtWithLength, source) == []
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

    test "does not flag when the index is not length-based" do
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
