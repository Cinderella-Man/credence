defmodule Credence.Pattern.NoGuardEqualityForPatternMatchFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoGuardEqualityForPatternMatch

  describe "fix" do
    test "does not modify integer guard (== matches 2.0 but the pattern head would not)" do
      code = "defp do_count(n, _a, b) when n == 2, do: b"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, code), code)
    end

    test "removes atom guard and substitutes parameter" do
      input = "def process(action) when action == :stop, do: :halted"

      expected = "def process(:stop), do: :halted"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "removes string guard and substitutes parameter" do
      input = ~S'def greet(name) when name == "world", do: "hi"'

      expected = ~S'def greet("world"), do: "hi"'

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "handles reversed equality (literal == var)" do
      input = "def foo(n) when :two == n, do: :ok"

      expected = "def foo(:two), do: :ok"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "keeps remaining condition in and-guard when var not referenced elsewhere" do
      input = "def foo(n, m) when n == :two and m > 0, do: m"

      expected = "def foo(:two, m) when m > 0, do: m"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "removes entire guard when all and-conditions are equalities" do
      input = "def foo(n, m) when n == :a and m == :b, do: :ok"

      expected = "def foo(:a, :b), do: :ok"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "does not modify or-guard" do
      code = "def foo(n) when n == 2 or n == 3, do: :ok"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, code), code)
    end

    test "does not modify when matched var appears in remaining guard" do
      code = "def foo(n) when is_integer(n) and n == 2, do: :ok"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, code), code)
    end

    test "does not modify when matched var appears in function body" do
      code = "def foo(n) when n == 2, do: n + 1"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, code), code)
    end

    test "does not modify when any of multiple matched vars appears in body" do
      code = "def foo(n, m) when n == 2 and m == 3, do: n + m"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, code), code)
    end

    test "fixes only the guarded clause in multi-clause function" do
      input = """
      defmodule Multi do
        def classify(n) when n == :zero, do: :zero
        def classify(n), do: n
      end
      """

      expected = """
      defmodule Multi do
        def classify(:zero), do: :zero
        def classify(n), do: n
      end
      """

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "does not modify functions without guard equalities" do
      code = """
      defmodule Plain do
        def foo(n), do: n
        def bar(n) when n > 0, do: n
      end
      """

      confirm_fix(fix(NoGuardEqualityForPatternMatch, code), code)
    end

    test "fixes multiple functions in same module" do
      input = """
      defmodule MultiFns do
        def foo(n) when n == :one, do: :one
        def bar(m) when m == :two, do: :two
      end
      """

      expected = """
      defmodule MultiFns do
        def foo(:one), do: :one
        def bar(:two), do: :two
      end
      """

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "preserves non-parameter patterns in function head" do
      input = "def foo(n, {a, b}) when n == :two, do: {a, b}"

      expected = "def foo(:two, {a, b}), do: {a, b}"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "works with defp" do
      input = "defp helper(n) when n == :answer, do: :found"

      expected = "defp helper(:answer), do: :found"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "works with reversed literal in compound and-guard" do
      input = "def foo(n, m) when :two == n and m > 0, do: m"

      expected = "def foo(:two, m) when m > 0, do: m"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "does not modify when var appears in nested expression in body" do
      code = "def foo(n) when n == 2, do: {:ok, n}"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, code), code)
    end

    test "fixes when body uses other variables but not the matched one" do
      input = "def foo(n, m) when n == :two, do: m * 2"

      expected = "def foo(:two, m), do: m * 2"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "does not modify comparison to composite types" do
      code = "def check(n) when n == %{a: 1}, do: :ok"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, code), code)
    end
  end

  # `nil` is an atom literal, so it must be substituted into the head like any
  # other atom. Previously the guard was dropped but `nil` was NOT substituted
  # (a `Map.get` nil-sentinel collision), leaving a clause that matched everything.
  describe "nil literal is substituted into the head" do
    test "removes nil guard and substitutes nil" do
      input = "def f(x) when x == nil, do: :was_nil"
      expected = "def f(nil), do: :was_nil"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "reversed equality (nil == var)" do
      input = "def f(x) when nil == x, do: :ok"
      expected = "def f(nil), do: :ok"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "nil among other parameters" do
      input = "def f(a, x, b) when x == nil, do: {a, b}"
      expected = "def f(a, nil, b), do: {a, b}"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "nil alongside an atom equality (both substituted, guard fully removed)" do
      input = "def f(x, y) when x == nil and y == :ok, do: :both"
      expected = "def f(nil, :ok), do: :both"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "nil substituted, a non-equality guard kept" do
      input = "def f(x, n) when x == nil and is_integer(n), do: n"
      expected = "def f(nil, n) when is_integer(n), do: n"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "the tds shape: nil clause keeps later same-arity clauses reachable" do
      input = """
      defmodule M do
        def encode(:int, value, _) when value == nil, do: <<0>>
        def encode(:int, value, _), do: <<value>>
      end
      """

      expected = """
      defmodule M do
        def encode(:int, nil, _), do: <<0>>
        def encode(:int, value, _), do: <<value>>
      end
      """

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "the tzdata shape: nil arg amid a cons pattern" do
      input = "def calc(a, [h | t], rules, c) when rules == nil, do: {a, h, t, c}"
      expected = "def calc(a, [h | t], nil, c), do: {a, h, t, c}"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    # This was a no-op, on the reasoning that "substituting x->nil would leave the
    # body referencing an unbound `x`". True of a bare substitution, and the wrong
    # conclusion: keep the binding and the body still has its variable. Executed
    # on `f(nil)`, `f(1)` and `f(false)`, before and after agree — `"nil"`,
    # `:other`, `:other`.
    test "keeps the binding when the body still references the matched variable" do
      input = "def f(x) when x == nil, do: inspect(x)"
      expected = "def f(nil = x), do: inspect(x)"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    test "keeps the binding when the remaining guard still references it" do
      input = "def f(n) when is_atom(n) and n == :two, do: n"
      expected = "def f(:two = n) when is_atom(n), do: n"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    # Regression for a silent miscompilation. The repeated `x` is a match
    # constraint: `f(:a, {:b, 2})` must NOT match this clause. Substituting the
    # literal into the first parameter alone dropped it, and executed, the result
    # went from `:nomatch` to `2` — compiling, warning-free, wrong.
    test "keeps the binding when another parameter repeats the variable" do
      input = "def f(x, {x, y}) when x == :a, do: y"
      expected = "def f(:a = x, {x, y}), do: y"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end

    # Per-variable, not all-or-nothing: only `x` is read afterwards.
    test "rebinds only the variables that are still read" do
      input = "def f(x, y) when x == nil and y == :ok, do: x"
      expected = "def f(nil = x, :ok), do: x"

      confirm_fix(fix(NoGuardEqualityForPatternMatch, input), expected)
    end
  end
end
