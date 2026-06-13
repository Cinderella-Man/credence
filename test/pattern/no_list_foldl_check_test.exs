defmodule Credence.Pattern.NoListFoldlCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoListFoldl

  describe "NoListFoldl" do
    test "detects List.foldl/3" do
      code = """
      defmodule Bad do
        def partition(list, pivot) do
          List.foldl(list, {[], 0, 1, []}, fn x, {l, l_len, e, g} ->
            cond do
              x < pivot -> {[x | l], l_len + 1, e, g}
              x == pivot -> {l, l_len, e + 1, g}
              true -> {l, l_len, e, [x | g]}
            end
          end)
        end
      end
      """

      [issue] = check(NoListFoldl, code)
      assert issue.rule == :no_list_foldl
      assert issue.message =~ "List.foldl/3"
      assert issue.message =~ "Enum.reduce/3"
    end

    test "detects List.foldl in a pipeline" do
      code = """
      defmodule Bad do
        def sum(list) do
          list |> List.foldl(0, &(&1 + &2))
        end
      end
      """

      [issue] = check(NoListFoldl, code)
      assert issue.message =~ "List.foldl/3"
    end

    test "detects multiple List.foldl calls in one module" do
      code = """
      defmodule Bad do
        def foo(list) do
          List.foldl(list, 0, fn x, acc -> acc + x end)
        end

        def bar(list) do
          List.foldl(list, [], fn x, acc -> [x | acc] end)
        end
      end
      """

      issues = check(NoListFoldl, code)
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.rule == :no_list_foldl))
    end

    # ---- Negative cases ----

    test "does not flag List.foldr (intentionally out of scope)" do
      code = """
      defmodule Neutral do
        def build(list) do
          List.foldr(list, [], fn x, acc -> [x * 2 | acc] end)
        end
      end
      """

      assert check(NoListFoldl, code) == []
    end

    test "does not flag Enum.reduce/3" do
      code = """
      defmodule Good do
        def sum(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert check(NoListFoldl, code) == []
    end

    test "does not flag :lists.foldl (Erlang direct call)" do
      code = """
      defmodule Neutral do
        def sum(list) do
          :lists.foldl(fn x, acc -> acc + x end, 0, list)
        end
      end
      """

      assert check(NoListFoldl, code) == []
    end

    test "does not flag custom module named List" do
      code = """
      defmodule Good do
        def foo(list) do
          MyApp.List.foldl(list, 0, &(&1 + &2))
        end
      end
      """

      assert check(NoListFoldl, code) == []
    end
  end
end
