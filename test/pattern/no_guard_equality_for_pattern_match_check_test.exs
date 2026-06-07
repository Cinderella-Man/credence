defmodule Credence.Pattern.NoGuardEqualityForPatternMatchCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoGuardEqualityForPatternMatch

  describe "check" do
    test "passes code that pattern matches directly in the head" do
      code = """
      defmodule GoodMatch do
        defp do_count(2, _a, b), do: b
        defp do_count(n, a, b), do: do_count(n - 1, b, a + b)
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "passes guards with non-equality comparisons" do
      code = """
      defmodule GoodGuard do
        def process(n) when is_integer(n) and n > 0 do
          n * 2
        end
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "passes guards comparing two variables" do
      code = """
      defmodule GoodVarGuard do
        def compare(a, b) when a == b, do: :equal
        def compare(_a, _b), do: :not_equal
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "does not flag integer literal (== matches 2.0 but the pattern head would not)" do
      code = """
      defmodule BadIntGuard do
        defp do_count(n, _a, b) when n == 2, do: b
        defp do_count(n, a, b), do: do_count(n - 1, b, a + b)
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "detects when var == atom_literal in guard (and reports metadata)" do
      code = """
      defmodule BadAtomMeta do
        defp step(s, _a, b) when s == :done, do: b
        defp step(s, a, b), do: step(s, b, a + b)
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_guard_equality_for_pattern_match

      assert issue.message =~ "s == :done"
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

      issues = check(NoGuardEqualityForPatternMatch, code)

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

      issues = check(NoGuardEqualityForPatternMatch, code)

      assert length(issues) == 1
      assert hd(issues).message =~ "world"
    end

    test "detects equality inside a compound guard" do
      code = """
      defmodule BadCompound do
        def process(s) when is_binary(s) and s == "zero", do: :zero
        def process(s) when is_binary(s), do: s
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)

      assert length(issues) == 1
      assert hd(issues).message =~ ~s(s == "zero")
    end

    test "ignores non-param variables in guard equality" do
      code = """
      defmodule SafeDestructure do
        def process(list) when is_list(list) do
          Enum.map(list, &(&1 * 2))
        end
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "detects only def/defp, not fn" do
      code = """
      defmodule SafeFn do
        def process(list) do
          Enum.filter(list, fn x -> x == 0 end)
        end
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "detects reversed equality (literal == var)" do
      code = """
      defmodule ReversedGuard do
        def process(n) when :two == n, do: :two
        def process(n), do: n
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 1
      assert hd(issues).message =~ "n == :two"
    end

    test "detects multiple equalities in and-guard" do
      code = """
      defmodule MultiGuard do
        def foo(n, m) when n == :two and m == :three, do: :ok
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 2

      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "n == :two"))
      assert Enum.any?(messages, &(&1 =~ "m == :three"))
    end

    test "detects equalities inside or-guard" do
      code = """
      defmodule OrGuard do
        def foo(n) when n == :two or n == :three, do: :ok
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 2
    end

    test "does not flag float literals" do
      code = """
      defmodule FloatGuard do
        def foo(n) when n == 2.0, do: :ok
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "flags true atom in guard" do
      code = """
      defmodule BoolGuard do
        def toggle(active) when active == true, do: :off
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 1
      assert hd(issues).message =~ "true"
    end

    test "flags nil atom in guard" do
      code = """
      defmodule NilGuard do
        def check(val) when val == nil, do: :empty
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 1
      assert hd(issues).message =~ "nil"
    end

    test "does not flag comparison to function call result" do
      code = """
      defmodule FuncGuard do
        def check(n) when n == System.pid(), do: :ok
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "detects equality mixed with other guards in and" do
      code = """
      defmodule MixedGuard do
        def foo(n) when is_atom(n) and n == :two, do: :ok
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 1
      assert hd(issues).message =~ "n == :two"
    end

    test "detects in def (not only defp)" do
      code = """
      defmodule DefGuard do
        def helper(n) when n == :answer, do: :found
        def helper(_), do: :not_found
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 1
      assert hd(issues).message =~ ":answer"
    end

    test "detects only the guarded clause in multi-clause function" do
      code = """
      defmodule MultiClause do
        def classify(n) when n == :zero, do: :zero
        def classify(n) when n > 0, do: :positive
        def classify(_n), do: :negative
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 1
      assert hd(issues).message =~ "n == :zero"
    end

    test "detects nested and/or combinations" do
      code = """
      defmodule NestedGuard do
        def foo(n, m, k) when (n == :two and m > 0) or k == :three, do: :ok
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 2

      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "n == :two"))
      assert Enum.any?(messages, &(&1 =~ "k == :three"))
    end

    test "does not flag comparison to composite types" do
      code = """
      defmodule CompositeGuard do
        def check_map(n) when n == %{a: 1}, do: :map
        def check_tuple(n) when n == {1, 2}, do: :tuple
        def check_list(n) when n == [1, 2], do: :list
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "does not flag charlist literal" do
      code = """
      defmodule CharlistGuard do
        def check(n) when n == ~c"hello", do: :ok
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "flags empty string literal" do
      code = """
      defmodule EmptyStringGuard do
        def check(s) when s == "", do: :empty
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 1
    end

    test "does not flag when variable is not a function parameter" do
      code = """
      defmodule NotParam do
        def foo(n) do
          x = compute(n)
          if x == 0, do: :zero, else: :other
        end
      end
      """

      assert check(NoGuardEqualityForPatternMatch, code) == []
    end

    test "detects equality for each guarded clause independently" do
      code = """
      defmodule MultiGuarded do
        def route(path) when path == "/admin", do: :admin
        def route(path) when path == "/login", do: :login
        def route(_path), do: :not_found
      end
      """

      issues = check(NoGuardEqualityForPatternMatch, code)
      assert length(issues) == 2

      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ ~s("/admin")))
      assert Enum.any?(messages, &(&1 =~ ~s("/login")))
    end
  end
end
