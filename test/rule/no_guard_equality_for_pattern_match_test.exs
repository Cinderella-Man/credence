defmodule Credence.Pattern.NoGuardEqualityForPatternMatchTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoGuardEqualityForPatternMatch.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoGuardEqualityForPatternMatch.fix(code, [])
  end

  # Compare fix result to expected code via AST to be formatting-agnostic
  defp assert_fix(input, expected) do
    result = fix(input)
    assert normalize(result) == normalize(expected)
  end

  # Assert that fix leaves the code semantically unchanged
  defp assert_fix_unchanged(input) do
    result = fix(input)
    assert normalize(result) == normalize(input)
  end

  defp normalize(code) do
    {_ok, ast} = Code.string_to_quoted(code)
    Macro.to_string(ast)
  end

  describe "check" do
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

    test "detects reversed equality (literal == var)" do
      code = """
      defmodule ReversedGuard do
        def process(n) when 2 == n, do: :two
        def process(n), do: n
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "n == 2"
    end

    test "detects multiple equalities in and-guard" do
      code = """
      defmodule MultiGuard do
        def foo(n, m) when n == 2 and m == 3, do: :ok
      end
      """

      issues = check(code)
      assert length(issues) == 2

      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "n == 2"))
      assert Enum.any?(messages, &(&1 =~ "m == 3"))
    end

    test "detects equalities inside or-guard" do
      code = """
      defmodule OrGuard do
        def foo(n) when n == 2 or n == 3, do: :ok
      end
      """

      issues = check(code)
      assert length(issues) == 2
    end

    test "does not flag float literals" do
      code = """
      defmodule FloatGuard do
        def foo(n) when n == 2.0, do: :ok
      end
      """

      assert check(code) == []
    end

    test "flags true atom in guard" do
      code = """
      defmodule BoolGuard do
        def toggle(active) when active == true, do: :off
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "true"
    end

    test "flags nil atom in guard" do
      code = """
      defmodule NilGuard do
        def check(val) when val == nil, do: :empty
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "nil"
    end

    test "does not flag comparison to function call result" do
      code = """
      defmodule FuncGuard do
        def check(n) when n == System.pid(), do: :ok
      end
      """

      assert check(code) == []
    end

    test "detects equality mixed with other guards in and" do
      code = """
      defmodule MixedGuard do
        def foo(n) when n > 0 and n == 2, do: :ok
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "n == 2"
    end

    test "detects in def (not only defp)" do
      code = """
      defmodule DefGuard do
        def helper(n) when n == 42, do: :found
        def helper(_), do: :not_found
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "42"
    end

    test "detects only the guarded clause in multi-clause function" do
      code = """
      defmodule MultiClause do
        def classify(n) when n == 0, do: :zero
        def classify(n) when n > 0, do: :positive
        def classify(_n), do: :negative
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).message =~ "n == 0"
    end

    test "detects nested and/or combinations" do
      code = """
      defmodule NestedGuard do
        def foo(n, m, k) when (n == 2 and m > 0) or k == 3, do: :ok
      end
      """

      issues = check(code)
      assert length(issues) == 2

      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "n == 2"))
      assert Enum.any?(messages, &(&1 =~ "k == 3"))
    end

    test "does not flag comparison to composite types" do
      code = """
      defmodule CompositeGuard do
        def check_map(n) when n == %{a: 1}, do: :map
        def check_tuple(n) when n == {1, 2}, do: :tuple
        def check_list(n) when n == [1, 2], do: :list
      end
      """

      assert check(code) == []
    end

    test "does not flag charlist literal" do
      code = """
      defmodule CharlistGuard do
        def check(n) when n == ~c"hello", do: :ok
      end
      """

      assert check(code) == []
    end

    test "flags empty string literal" do
      code = """
      defmodule EmptyStringGuard do
        def check(s) when s == "", do: :empty
      end
      """

      issues = check(code)
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

      assert check(code) == []
    end

    test "detects equality for each guarded clause independently" do
      code = """
      defmodule MultiGuarded do
        def route(path) when path == "/admin", do: :admin
        def route(path) when path == "/login", do: :login
        def route(_path), do: :not_found
      end
      """

      issues = check(code)
      assert length(issues) == 2

      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ ~s("/admin")))
      assert Enum.any?(messages, &(&1 =~ ~s("/login")))
    end
  end

  describe "fix" do
    test "removes simple integer guard and substitutes parameter" do
      assert_fix(
        "defp do_count(n, _a, b) when n == 2, do: b",
        "defp do_count(2, _a, b), do: b"
      )
    end

    test "removes atom guard and substitutes parameter" do
      assert_fix(
        "def process(action) when action == :stop, do: :halted",
        "def process(:stop), do: :halted"
      )
    end

    test "removes string guard and substitutes parameter" do
      assert_fix(
        "def greet(name) when name == \"world\", do: \"hi\"",
        "def greet(\"world\"), do: \"hi\""
      )
    end

    test "handles reversed equality (literal == var)" do
      assert_fix(
        "def foo(n) when 2 == n, do: :ok",
        "def foo(2), do: :ok"
      )
    end

    test "keeps remaining condition in and-guard when var not referenced elsewhere" do
      assert_fix(
        "def foo(n, m) when n == 2 and m > 0, do: m",
        "def foo(2, m) when m > 0, do: m"
      )
    end

    test "removes entire guard when all and-conditions are equalities" do
      assert_fix(
        "def foo(n, m) when n == 2 and m == 3, do: :ok",
        "def foo(2, 3), do: :ok"
      )
    end

    test "does not modify or-guard" do
      assert_fix_unchanged("def foo(n) when n == 2 or n == 3, do: :ok")
    end

    test "does not modify when matched var appears in remaining guard" do
      assert_fix_unchanged("def foo(n) when is_integer(n) and n == 2, do: :ok")
    end

    test "does not modify when matched var appears in function body" do
      assert_fix_unchanged("def foo(n) when n == 2, do: n + 1")
    end

    test "does not modify when any of multiple matched vars appears in body" do
      assert_fix_unchanged("def foo(n, m) when n == 2 and m == 3, do: n + m")
    end

    test "fixes only the guarded clause in multi-clause function" do
      code = """
      defmodule Multi do
        def classify(n) when n == 0, do: :zero
        def classify(n), do: n
      end
      """

      expected = """
      defmodule Multi do
        def classify(0), do: :zero
        def classify(n), do: n
      end
      """

      assert_fix(code, expected)
    end

    test "does not modify functions without guard equalities" do
      code = """
      defmodule Plain do
        def foo(n), do: n
        def bar(n) when n > 0, do: n
      end
      """

      assert_fix_unchanged(code)
    end

    test "fixes multiple functions in same module" do
      code = """
      defmodule MultiFns do
        def foo(n) when n == 1, do: :one
        def bar(m) when m == 2, do: :two
      end
      """

      expected = """
      defmodule MultiFns do
        def foo(1), do: :one
        def bar(2), do: :two
      end
      """

      assert_fix(code, expected)
    end

    test "preserves non-parameter patterns in function head" do
      assert_fix(
        "def foo(n, {a, b}) when n == 2, do: {a, b}",
        "def foo(2, {a, b}), do: {a, b}"
      )
    end

    test "works with defp" do
      assert_fix(
        "defp helper(n) when n == 42, do: :found",
        "defp helper(42), do: :found"
      )
    end

    test "works with reversed literal in compound and-guard" do
      assert_fix(
        "def foo(n, m) when 2 == n and m > 0, do: m",
        "def foo(2, m) when m > 0, do: m"
      )
    end

    test "does not modify when var appears in nested expression in body" do
      assert_fix_unchanged("def foo(n) when n == 2, do: {:ok, n}")
    end

    test "fixes when body uses other variables but not the matched one" do
      assert_fix(
        "def foo(n, m) when n == 2, do: m * 2",
        "def foo(2, m), do: m * 2"
      )
    end

    test "does not modify comparison to composite types" do
      assert_fix_unchanged("def check(n) when n == %{a: 1}, do: :ok")
    end
  end
end
