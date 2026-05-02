defmodule Credence.Rule.NoGuardEqualityForPatternMatchTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoGuardEqualityForPatternMatch.check(ast, [])
  end

  describe "NoGuardEqualityForPatternMatch" do
    test "passes code that pattern matches directly in the head" do
      code = """
      defmodule GoodMatch do
        defp do_count(2, _a, b), do: b
        defp do_count(n, a, b), do: do_count(n - 1, b, a + b)
      end
      """

      assert check(code) == []
    end

    test "passes guards with non-equality comparisons" do
      code = """
      defmodule GoodGuard do
        def process(n) when is_integer(n) and n > 0 do
          n * 2
        end
      end
      """

      assert check(code) == []
    end

    test "passes guards comparing two variables" do
      code = """
      defmodule GoodVarGuard do
        def compare(a, b) when a == b, do: :equal
        def compare(_a, _b), do: :not_equal
      end
      """

      assert check(code) == []
    end

    test "detects when var == integer_literal in guard" do
      code = """
      defmodule BadIntGuard do
        defp do_count(n, _a, b) when n == 2, do: b
        defp do_count(n, a, b), do: do_count(n - 1, b, a + b)
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_guard_equality_for_pattern_match

      assert issue.message =~ "n == 2"
      assert issue.message =~ "pattern matching"
      assert issue.meta.line != nil
    end

    test "detects when var == atom_literal in guard" do
      code = """
      defmodule BadAtomGuard do
        def process(action) when action == :stop, do: :halted
        def process(_action), do: :running
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).message =~ ":stop"
    end

    test "detects when var == string_literal in guard" do
      code = """
      defmodule BadStringGuard do
        def greet(name) when name == "world", do: "Hello, world!"
        def greet(name), do: "Hi, \#{name}!"
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).message =~ "world"
    end

    test "detects equality inside a compound guard" do
      code = """
      defmodule BadCompound do
        def process(n) when is_integer(n) and n == 0, do: :zero
        def process(n) when is_integer(n), do: n
      end
      """

      issues = check(code)

      assert length(issues) == 1
      assert hd(issues).message =~ "n == 0"
    end

    test "ignores non-param variables in guard equality" do
      # Guards with == on destructured bindings from patterns like [h | _]
      # are excluded because h is not a top-level param name.
      code = """
      defmodule SafeDestructure do
        def process(list) when is_list(list) do
          Enum.map(list, &(&1 * 2))
        end
      end
      """

      assert check(code) == []
    end

    test "detects only def/defp, not fn" do
      code = """
      defmodule SafeFn do
        def process(list) do
          Enum.filter(list, fn x -> x == 0 end)
        end
      end
      """

      assert check(code) == []
    end
  end
end
