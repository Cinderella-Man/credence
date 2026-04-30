defmodule Credence.Rule.NoIsPrefixTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoIsPrefix.check(ast, [])
  end

  describe "NoIsPrefix" do
    test "passes functions with ? suffix" do
      code = """
      defmodule GoodPredicates do
        def valid?(x), do: x > 0
        def palindrome?(s), do: s == String.reverse(s)
        defp empty?(list), do: list == []
      end
      """

      assert check(code) == []
    end

    test "passes non-predicate functions" do
      code = """
      defmodule NormalFunctions do
        def process(x), do: x * 2
        def calculate_sum(list), do: Enum.sum(list)
        defp helper(x), do: x + 1
      end
      """

      assert check(code) == []
    end

    test "passes Erlang guard-safe BIF wrappers" do
      code = """
      defmodule GuardWrappers do
        def check(x) when is_integer(x), do: :ok
        def check(x) when is_list(x), do: :ok
        def check(x) when is_binary(x), do: :ok
      end
      """

      assert check(code) == []
    end

    test "detects is_ prefix on public function" do
      code = """
      defmodule BadPredicate do
        def is_valid_palindrome(s) when is_binary(s) do
          cleaned = String.downcase(s)
          cleaned == String.reverse(cleaned)
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_is_prefix
      assert issue.severity == :info
      assert issue.message =~ "is_valid_palindrome"
      assert issue.message =~ "?"
      assert issue.meta.line != nil
    end

    test "detects is_ prefix on private function" do
      code = """
      defmodule BadPrivate do
        defp is_empty(list), do: list == []
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).message =~ "is_empty"
      assert hd(issues).message =~ "empty?"
    end

    test "detects multiple is_ prefix functions" do
      code = """
      defmodule MultipleBad do
        def is_valid(x), do: x > 0
        def is_palindrome(s), do: s == String.reverse(s)
        defp is_sorted(list), do: list == Enum.sort(list)
      end
      """

      issues = check(code)

      assert length(issues) == 3
    end

    test "deduplicates multi-clause functions" do
      code = """
      defmodule MultiClause do
        def is_even(0), do: true
        def is_even(n) when n > 0, do: rem(n, 2) == 0
        def is_even(_), do: false
      end
      """

      issues = check(code)

      # Should report once, not three times
      assert length(issues) == 1
      assert hd(issues).message =~ "is_even"
    end
  end
end
