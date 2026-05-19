defmodule Credence.Pattern.NoRepeatedEnumTraversalTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoRepeatedEnumTraversal.check(ast, [])
  end

  describe "NoRepeatedEnumTraversal" do
    # --- POSITIVE CASES (should flag) ---

    test "detects repeated traversal of same enumerable" do
      code = """
      defmodule Stats do
        def stats(list) do
          max = Enum.max(list)
          min = Enum.min(list)
          count = Enum.count(list)
          {max, min, count}
        end
      end
      """

      issues = check(code)
      assert length(issues) == 3

      Enum.each(issues, fn issue ->
        assert %Issue{} = issue
        assert issue.rule == :no_repeated_enum_traversal
        assert issue.message =~ "Repeated traversal"
        assert issue.message =~ "Enum"
        assert issue.meta.line != nil
      end)
    end

    test "detects repeated traversal inside conditionals" do
      code = """
      defmodule Conditional do
        def check(list) do
          if Enum.member?(list, 10) and Enum.member?(list, 20) do
            Enum.count(list)
          else
            0
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 3
    end

    test "detects repeated traversal with mixed Enum functions" do
      code = """
      defmodule Mixed do
        def process(list) do
          Enum.any?(list)
          Enum.find(list, &(&1 > 10))
          Enum.count(list)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 3
    end

    test "detects repeated traversal with sum and count" do
      code = """
      defmodule Metrics do
        def compute(data) do
          total = Enum.sum(data)
          n = Enum.count(data)
          total / n
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "detects repeated traversal with member? and find" do
      code = """
      defmodule Lookup do
        def search(items) do
          if Enum.member?(items, :target) do
            Enum.find(items, &(&1 == :target))
          end
        end
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "detects repeated traversal across multiple functions" do
      code = """
      defmodule MultiFunc do
        def analyze(list) do
          first_pass(list)
          second_pass(list)
        end

        defp first_pass(list), do: Enum.count(list)
        defp second_pass(list), do: Enum.max(list)
      end
      """

      # Both calls use the same variable name `list` in their own scope,
      # but each function has its own scope. The AST walk sees them as
      # separate scopes, but var_name doesn't distinguish scopes — both
      # will be tracked as :list. This is a known limitation.
      issues = check(code)
      assert length(issues) == 2
    end

    test "reports correct function names in messages" do
      code = """
      defmodule FuncNames do
        def go(list) do
          Enum.max(list)
          Enum.min(list)
        end
      end
      """

      issues = check(code)
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "Enum.max/1"))
      assert Enum.any?(messages, &(&1 =~ "Enum.min/1"))
    end

    test "reports correct arity for 2-arity functions" do
      code = """
      defmodule ArityCheck do
        def go(list) do
          Enum.member?(list, 1)
          Enum.find(list, &(&1 > 5))
        end
      end
      """

      issues = check(code)
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "Enum.member?/2"))
      assert Enum.any?(messages, &(&1 =~ "Enum.find/2"))
    end

    # --- NEGATIVE CASES (should NOT flag) ---

    test "passes when enumerable is traversed once" do
      code = """
      defmodule GoodCode do
        def count(list) do
          Enum.count(list)
        end
      end
      """

      assert check(code) == []
    end

    test "passes when multiple enumerables are traversed multiple times" do
      code = """
      defmodule GoodCode do
        def count(list) do
          Enum.count(list)
          Enum.sort([1, 2, 3])
          Enum.count([1, 2, 3, 4])
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag different variables" do
      code = """
      defmodule DifferentLists do
        def compare(a, b) do
          {Enum.max(a), Enum.max(b)}
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag single Enum call" do
      code = """
      defmodule Single do
        def run(list), do: Enum.sum(list)
      end
      """

      assert check(code) == []
    end

    test "does not flag non-Enum traversals" do
      code = """
      defmodule NotEnum do
        def run(list) do
          String.length(list)
          String.upcase(list)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum functions not in traversal list" do
      code = """
      defmodule NonTraversal do
        def run(list) do
          Enum.sort(list)
          Enum.reverse(list)
          Enum.map(list, & &1)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag when argument is not a variable" do
      code = """
      defmodule LiteralArg do
        def run do
          Enum.count([1, 2, 3])
          Enum.max([1, 2, 3])
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag Enum.at and similar non-traversal functions" do
      code = """
      defmodule NonFlagged do
        def run(list) do
          Enum.at(list, 0)
          Enum.at(list, 1)
          Enum.at(list, 2)
        end
      end
      """

      assert check(code) == []
    end

    test "fixable? returns false" do
      assert Credence.Pattern.NoRepeatedEnumTraversal.fixable?() == false
    end
  end
end
