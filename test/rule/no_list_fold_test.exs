defmodule Credence.Rule.NoListFoldTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoListFold.check(ast, [])
  end

  describe "NoListFold" do
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

      [issue] = check(code)
      assert issue.rule == :no_list_fold

      assert issue.message =~ "List.foldl/3"
      assert issue.message =~ "Enum.reduce/3"
    end

    test "detects List.foldr/3" do
      code = """
      defmodule Bad do
        def build(list) do
          List.foldr(list, [], fn x, acc -> [x * 2 | acc] end)
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "List.foldr/3"
      assert issue.message =~ "Enum.reduce/3"
      assert issue.message =~ "reverse"
    end

    test "detects multiple fold calls in one module" do
      code = """
      defmodule Bad do
        def foo(list) do
          List.foldl(list, 0, fn x, acc -> acc + x end)
        end

        def bar(list) do
          List.foldr(list, [], fn x, acc -> [x | acc] end)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
      rules = Enum.map(issues, & &1.rule)
      assert Enum.all?(rules, &(&1 == :no_list_fold))
    end

    test "detects List.foldl in a pipeline" do
      code = """
      defmodule Bad do
        def sum(list) do
          list |> List.foldl(0, &(&1 + &2))
        end
      end
      """

      [issue] = check(code)
      assert issue.message =~ "List.foldl/3"
    end

    # ---- Negative cases ----

    test "does not flag Enum.reduce/3" do
      code = """
      defmodule Good do
        def sum(list) do
          Enum.reduce(list, 0, fn x, acc -> acc + x end)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag :lists.foldl (Erlang direct call)" do
      code = """
      defmodule Neutral do
        def sum(list) do
          :lists.foldl(fn x, acc -> acc + x end, 0, list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag List.first or other List functions" do
      code = """
      defmodule Good do
        def head(list) do
          List.first(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag custom module named List" do
      code = """
      defmodule Good do
        def foo(list) do
          MyApp.List.foldl(list, 0, &(&1 + &2))
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag unrelated code" do
      code = """
      defmodule Good do
        def foo(list) do
          list
          |> Enum.map(&(&1 * 2))
          |> Enum.filter(&(&1 > 0))
        end
      end
      """

      assert check(code) == []
    end
  end
end
