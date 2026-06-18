defmodule Credence.Pattern.NoDuplicateFunctionClausesCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoDuplicateFunctionClauses

  describe "does not flag" do
    test "single-clause function" do
      assert clean?(NoDuplicateFunctionClauses, """
             defmodule Good do
               def bar(x, y), do: {x, y}
             end
             """)
    end

    test "multi-clause function with different patterns" do
      assert clean?(NoDuplicateFunctionClauses, """
             defmodule Good do
               def bar(0, y), do: {:zero, y}
               def bar(x, y), do: {x, y}
             end
             """)
    end

    test "different function names" do
      assert clean?(NoDuplicateFunctionClauses, """
             defmodule Good do
               def bar(x, y), do: {x, y}
               def baz(x, y), do: {x, y}
             end
             """)
    end

    test "different arities" do
      assert clean?(NoDuplicateFunctionClauses, """
             defmodule Good do
               def bar(x), do: x
               def bar(x, y), do: {x, y}
             end
             """)
    end

    test "no functions at all" do
      assert clean?(NoDuplicateFunctionClauses, """
             defmodule Good do
               @x 42
             end
             """)
    end

    test "different variable names count as same pattern (bare vars)" do
      # def bar(x, y) and def bar(a, b) have the same normalized pattern
      assert flagged?(NoDuplicateFunctionClauses, """
             defmodule Bad do
               def bar(x, y), do: {x, y}
               def bar(a, b), do: {a, b}
             end
             """)
    end

    test "different guard makes clauses non-duplicate" do
      assert clean?(NoDuplicateFunctionClauses, """
             defmodule Good do
               def bar(x, y) when is_integer(x), do: {x, y}
               def bar(x, y), do: {x, y}
             end
             """)
    end
  end

  describe "flags" do
    test "two identical clauses" do
      issues =
        check(NoDuplicateFunctionClauses, """
        defmodule Bad do
          def bar(x, y), do: {x, y}
          def bar(x, y), do: {x, y}
        end
        """)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_duplicate_function_clauses
      assert issue.message =~ "Duplicate"
      assert issue.message =~ "bar/2"
      assert issue.meta.line != nil
    end

    test "three identical clauses" do
      issues =
        check(NoDuplicateFunctionClauses, """
        defmodule Bad do
          def bar(x, y), do: {x, y}
          def bar(x, y), do: {x, y}
          def bar(x, y), do: {x, y}
        end
        """)

      assert length(issues) == 2
    end

    test "duplicate with different variable names" do
      issues =
        check(NoDuplicateFunctionClauses, """
        defmodule Bad do
          def bar(x, y), do: {x, y}
          def bar(a, b), do: {a, b}
        end
        """)

      assert length(issues) == 1
    end

    test "duplicate defp clauses" do
      issues =
        check(NoDuplicateFunctionClauses, """
        defmodule Bad do
          defp helper(x, y), do: {x, y}
          defp helper(x, y), do: {x, y}
        end
        """)

      assert length(issues) == 1
    end

    test "duplicate clauses with multi-line body" do
      issues =
        check(NoDuplicateFunctionClauses, """
        defmodule Bad do
          def bar(x, y) do
            {x, y}
          end

          def bar(x, y) do
            {x, y}
          end
        end
        """)

      assert length(issues) == 1
    end
  end

  describe "macro-generated clauses (unquote in head)" do
    # Inside a `quote`, `def f(unquote(a))` and `def f(unquote(b))` expand to
    # different literal patterns, so they are NOT duplicates — but the surface
    # AST collapses every `unquote(var)` to the same placeholder, which would
    # make them look identical. A head containing `unquote` must be skipped.
    test "does not flag clauses whose head contains unquote" do
      issues =
        check(NoDuplicateFunctionClauses, """
        defmodule Bad do
          defmacro gen do
            quote do
              def to_num(unquote(lower)), do: 1
              def to_num(unquote(upper)), do: 2
            end
          end
        end
        """)

      assert issues == []
    end

    test "still flags genuinely-identical clauses inside a quote (no unquote)" do
      issues =
        check(NoDuplicateFunctionClauses, """
        defmodule Bad do
          defmacro gen do
            quote do
              def to_num(:a), do: 1
              def to_num(:a), do: 2
            end
          end
        end
        """)

      assert length(issues) == 1
    end
  end
end
