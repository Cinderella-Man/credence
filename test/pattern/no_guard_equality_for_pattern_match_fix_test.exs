defmodule Credence.Pattern.NoGuardEqualityForPatternMatchFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoGuardEqualityForPatternMatch

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoGuardEqualityForPatternMatch, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "does not modify integer guard (== matches 2.0 but the pattern head would not)" do
      code = """
      defp do_count(n, _a, b) when n == 2, do: b
      """

      assert fix(code) == code
    end

    test "removes atom guard and substitutes parameter" do
      input = """
      def process(action) when action == :stop, do: :halted
      """

      expected = """
      def process(:stop), do: :halted
      """

      assert fix(input) == expected
    end

    test "removes string guard and substitutes parameter" do
      input = """
      def greet(name) when name == "world", do: "hi"
      """

      expected = """
      def greet("world"), do: "hi"
      """

      assert fix(input) == expected
    end

    test "handles reversed equality (literal == var)" do
      input = """
      def foo(n) when :two == n, do: :ok
      """

      expected = """
      def foo(:two), do: :ok
      """

      assert fix(input) == expected
    end

    test "keeps remaining condition in and-guard when var not referenced elsewhere" do
      input = """
      def foo(n, m) when n == :two and m > 0, do: m
      """

      expected = """
      def foo(:two, m) when m > 0, do: m
      """

      assert fix(input) == expected
    end

    test "removes entire guard when all and-conditions are equalities" do
      input = """
      def foo(n, m) when n == :a and m == :b, do: :ok
      """

      expected = """
      def foo(:a, :b), do: :ok
      """

      assert fix(input) == expected
    end

    test "does not modify or-guard" do
      code = """
      def foo(n) when n == 2 or n == 3, do: :ok
      """

      assert fix(code) == code
    end

    test "does not modify when matched var appears in remaining guard" do
      code = """
      def foo(n) when is_integer(n) and n == 2, do: :ok
      """

      assert fix(code) == code
    end

    test "does not modify when matched var appears in function body" do
      code = """
      def foo(n) when n == 2, do: n + 1
      """

      assert fix(code) == code
    end

    test "does not modify when any of multiple matched vars appears in body" do
      code = """
      def foo(n, m) when n == 2 and m == 3, do: n + m
      """

      assert fix(code) == code
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

      assert fix(input) == expected
    end

    test "does not modify functions without guard equalities" do
      code = """
      defmodule Plain do
        def foo(n), do: n
        def bar(n) when n > 0, do: n
      end
      """

      assert fix(code) == code
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

      assert fix(input) == expected
    end

    test "preserves non-parameter patterns in function head" do
      input = """
      def foo(n, {a, b}) when n == :two, do: {a, b}
      """

      expected = """
      def foo(:two, {a, b}), do: {a, b}
      """

      assert fix(input) == expected
    end

    test "works with defp" do
      input = """
      defp helper(n) when n == :answer, do: :found
      """

      expected = """
      defp helper(:answer), do: :found
      """

      assert fix(input) == expected
    end

    test "works with reversed literal in compound and-guard" do
      input = """
      def foo(n, m) when :two == n and m > 0, do: m
      """

      expected = """
      def foo(:two, m) when m > 0, do: m
      """

      assert fix(input) == expected
    end

    test "does not modify when var appears in nested expression in body" do
      code = """
      def foo(n) when n == 2, do: {:ok, n}
      """

      assert fix(code) == code
    end

    test "fixes when body uses other variables but not the matched one" do
      input = """
      def foo(n, m) when n == :two, do: m * 2
      """

      expected = """
      def foo(:two, m), do: m * 2
      """

      assert fix(input) == expected
    end

    test "does not modify comparison to composite types" do
      code = """
      def check(n) when n == %{a: 1}, do: :ok
      """

      assert fix(code) == code
    end
  end
end
