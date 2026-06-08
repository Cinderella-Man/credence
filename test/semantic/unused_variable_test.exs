defmodule Credence.Semantic.UnusedVariableTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [valid_syntax?: 1]

  alias Credence.Semantic.UnusedVariable
  # ── Unit tests (rule logic with synthetic diagnostics) ──────────

  describe "match?/1" do
    test "matches unused variable warning" do
      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: {5, 6}
      }

      assert UnusedVariable.match?(diag)
    end

    test "does not match unused function warning" do
      diag = %{severity: :warning, message: "function helper/1 is unused", position: {5, 6}}
      refute UnusedVariable.match?(diag)
    end

    test "does not match error severity" do
      diag = %{
        severity: :error,
        message: """
        variable "x" is unused
        """,
        position: {5, 6}
      }

      refute UnusedVariable.match?(diag)
    end

    test "does not match unrelated warning" do
      diag = %{severity: :warning, message: "some other warning", position: {5, 6}}
      refute UnusedVariable.match?(diag)
    end
  end

  describe "fix/2 (unit)" do
    test "prefixes unused variable with underscore" do
      source = """
      def run(list) do
        {current, max} = compute(list)
        max
      end
      """

      diag = %{
        severity: :warning,
        message: """
        variable "current" is unused
        """,
        position: {2, 4}
      }

      expected = """
      def run(list) do
        {_current, max} = compute(list)
        max
      end
      """

      assert UnusedVariable.fix(source, diag) == expected
    end

    test "does not double-prefix already underscored variable" do
      source = """
      def run(list) do
        {_current, max} = compute(list)
        max
      end
      """

      diag = %{
        severity: :warning,
        message: """
        variable "_current" is unused
        """,
        position: {2, 4}
      }

      # Already underscored — left untouched.
      assert UnusedVariable.fix(source, diag) == source
    end

    test "fixes on correct line only" do
      source = """
      total = compute()
      {total, extra} = split(data)
      total
      """

      diag = %{
        severity: :warning,
        message: """
        variable "extra" is unused
        """,
        position: {2, 9}
      }

      expected = """
      total = compute()
      {total, _extra} = split(data)
      total
      """

      assert UnusedVariable.fix(source, diag) == expected
    end

    test "handles position as bare integer" do
      source = """
      x = 1

      """

      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: 1
      }

      assert UnusedVariable.fix(source, diag) == """
             _x = 1

             """
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{
        severity: :warning,
        message: """
        variable "foo" is unused
        """,
        position: {7, 4}
      }

      issue = UnusedVariable.to_issue(diag)
      assert issue.rule == :unused_variable
      assert issue.meta.line == 7
      assert issue.message =~ "foo"
    end
  end

  # ── Integration tests (through Credence.Semantic coordinator) ───

  describe "integration through Credence.Semantic" do
    test "detects unused variable in tuple destructuring" do
      source = """
      defmodule UnusedVarInteg1 do
        def run do
          {current, max} = {1, 2}
          max
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      unused = Enum.filter(issues, &(&1.rule == :unused_variable))
      assert length(unused) == 1
      assert hd(unused).message =~ "current"
    end

    test "fixes unused variable in tuple destructuring" do
      source = """
      defmodule UnusedVarInteg2 do
        def run do
          {current, max} = {1, 2}
          max
        end
      end
      """

      expected = """
      defmodule UnusedVarInteg2 do
        def run do
          {_current, max} = {1, 2}
          max
        end
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end

    test "no issues when all variables are used" do
      source = """
      defmodule UnusedVarInteg3 do
        def run(a, b) do
          a + b
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      unused = Enum.filter(issues, &(&1.rule == :unused_variable))
      assert unused == []
    end

    test "no issues when variable already prefixed with underscore" do
      source = """
      defmodule UnusedVarInteg4 do
        def run do
          {_current, max} = {1, 2}
          max
        end
      end
      """

      issues = Credence.Semantic.analyze(source)
      unused = Enum.filter(issues, &(&1.rule == :unused_variable))
      assert unused == []
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Regression: binding-name conflict on the same line
  # ════════════════════════════════════════════════════════════════

  describe "binding-name conflict on same line (REGRESSION)" do
    test "string-keyed map, binding matches key (LiveView handle_event — original report)" do
      source = """
      defmodule LiveEvent do
        def handle_event("move-to", %{"destination" => destination} = params, socket) do
          IO.inspect(params)
          {:noreply, socket}
        end
      end
      """

      expected = """
      defmodule LiveEvent do
        def handle_event("move-to", %{"destination" => _destination} = params, socket) do
          IO.inspect(params)
          {:noreply, socket}
        end
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end

    test "atom-keyed map, binding matches key" do
      source = """
      defmodule Atomic do
        def get(%{foo: foo}), do: :ok
      end
      """

      expected = """
      defmodule Atomic do
        def get(%{foo: _foo}), do: :ok
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end

    test "function name contains the binding name as a substring" do
      source = """
      defmodule Fns do
        def destination_helper(destination), do: nil
      end
      """

      expected = """
      defmodule Fns do
        def destination_helper(_destination), do: nil
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end

    test "function name ENDS with the binding's letters" do
      source = """
      defmodule Ending do
        def index(:a, x), do: :ok
        def index(:b, x), do: x
      end
      """

      expected = """
      defmodule Ending do
        def index(:a, _x), do: :ok
        def index(:b, x), do: x
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Common destructuring shapes
  # ════════════════════════════════════════════════════════════════

  describe "common destructuring shapes" do
    test "nested tuple pattern with unused inner element" do
      source = """
      defmodule Nested do
        def f({outer, inner}), do: outer
      end
      """

      expected = """
      defmodule Nested do
        def f({outer, _inner}), do: outer
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end

    test "list cons pattern with unused tail" do
      source = """
      defmodule Lst do
        def f([head | tail]), do: head
      end
      """

      expected = """
      defmodule Lst do
        def f([head | _tail]), do: head
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end

    test "lambda argument unused" do
      source = """
      defmodule Lam do
        def f(list), do: Enum.map(list, fn x -> 1 end)
      end
      """

      expected = """
      defmodule Lam do
        def f(list), do: Enum.map(list, fn _x -> 1 end)
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end

    test "multi-clause function — only the clause whose arg is unused gets touched" do
      source = """
      defmodule Multi do
        def f(:a, x), do: :ok
        def f(:b, x), do: x
      end
      """

      expected = """
      defmodule Multi do
        def f(:a, _x), do: :ok
        def f(:b, x), do: x
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end

    test "case clause with unused binding" do
      source = """
      defmodule CaseTest do
        def f(x) do
          case x do
            {:ok, val} -> :ok
            _ -> :error
          end
        end
      end
      """

      expected = """
      defmodule CaseTest do
        def f(x) do
          case x do
            {:ok, _val} -> :ok
            _ -> :error
          end
        end
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Multiple unused bindings on a single line.
  # ════════════════════════════════════════════════════════════════

  describe "multiple unused on same line" do
    test "two unused in flat tuple — both underscored" do
      source = """
      defmodule Both do
        def f do
          {a, b} = {1, 2}
          :ok
        end
      end
      """

      expected = """
      defmodule Both do
        def f do
          {_a, _b} = {1, 2}
          :ok
        end
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end

    test "three unused in nested pattern — all underscored, structure intact" do
      source = """
      defmodule Triple do
        def f do
          {a, {b, c}} = {1, {2, 3}}
          :ok
        end
      end
      """

      expected = """
      defmodule Triple do
        def f do
          {_a, {_b, _c}} = {1, {2, 3}}
          :ok
        end
      end
      """

      assert Credence.Semantic.fix(source) == expected
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Negative cases: nothing to fix because the compiler emits no warning.
  # ════════════════════════════════════════════════════════════════

  describe "should NOT trigger" do
    test "variable used in the body — no warning" do
      source = """
      defmodule Used do
        def f(x), do: x
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.filter(issues, &(&1.rule == :unused_variable)) == []
    end

    test "variable used only in a guard — no warning" do
      source = """
      defmodule UsedGuard do
        def f(x) when is_atom(x), do: :ok
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.filter(issues, &(&1.rule == :unused_variable)) == []
    end

    test "bare `_` placeholder — no warning" do
      source = """
      defmodule BareU do
        def f(_, b), do: b
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.filter(issues, &(&1.rule == :unused_variable)) == []
    end

    test "intentional pattern-match equality (`x, x`) is not flagged" do
      source = """
      defmodule Eq do
        def f(x, x), do: x
      end
      """

      issues = Credence.Semantic.analyze(source)
      assert Enum.filter(issues, &(&1.rule == :unused_variable)) == []
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Safety guards on `fix/2`.
  # ════════════════════════════════════════════════════════════════

  describe "fix/2 — safety guards" do
    test "no column AND var name appears more than once on the line — skip" do
      source = """
        %{"foo" => foo} = params

      """

      diag = %{
        severity: :warning,
        message: """
        variable "foo" is unused
        """,
        position: 1
      }

      assert UnusedVariable.fix(source, diag) == source
    end

    test "column points past the end of the line — skip" do
      source = """
      x = 1

      """

      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: {1, 100}
      }

      assert UnusedVariable.fix(source, diag) == source
    end

    test "text at the given column does not start with the var name — skip" do
      source = """
      y = x

      """

      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: {1, 1}
      }

      assert UnusedVariable.fix(source, diag) == source
    end
  end

  describe "fix output is well-formed" do
    test "fixed output parses" do
      source = """
      def run(list) do
        {current, max} = compute(list)
        max
      end
      """

      diag = %{
        severity: :warning,
        message: """
        variable "current" is unused
        """,
        position: {2, 4}
      }

      assert valid_syntax?(UnusedVariable.fix(source, diag))
    end
  end
end
