defmodule Credence.Semantic.UnusedVariableTest do
  use ExUnit.Case

  alias Credence.Semantic.UnusedVariable
  # ── Unit tests (rule logic with synthetic diagnostics) ──────────

  describe "match?/1" do
    test "matches unused variable warning" do
      diag = %{severity: :warning, message: ~s(variable "x" is unused), position: {5, 6}}
      assert UnusedVariable.match?(diag)
    end

    test "does not match unused function warning" do
      diag = %{severity: :warning, message: "function helper/1 is unused", position: {5, 6}}
      refute UnusedVariable.match?(diag)
    end

    test "does not match error severity" do
      diag = %{severity: :error, message: ~s(variable "x" is unused), position: {5, 6}}
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
        message: ~s(variable "current" is unused),
        position: {2, 4}
      }

      fixed = UnusedVariable.fix(source, diag)
      assert fixed =~ "_current"
      assert fixed =~ "max"
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
        message: ~s(variable "_current" is unused),
        position: {2, 4}
      }

      fixed = UnusedVariable.fix(source, diag)
      refute fixed =~ "__current"
    end

    test "fixes on correct line only" do
      source = """
      total = compute()
      {total, extra} = split(data)
      total
      """

      diag = %{
        severity: :warning,
        message: ~s(variable "extra" is unused),
        position: {2, 9}
      }

      fixed = UnusedVariable.fix(source, diag)
      # Only line 2 should be modified
      lines = String.split(fixed, "\n")
      assert Enum.at(lines, 1) =~ "_extra"
      # Line 1 and 3 untouched
      assert Enum.at(lines, 0) =~ "total = compute()"
      assert Enum.at(lines, 2) =~ "total"
    end

    test "handles position as bare integer" do
      source = "x = 1\n"

      diag = %{
        severity: :warning,
        message: ~s(variable "x" is unused),
        position: 1
      }

      fixed = UnusedVariable.fix(source, diag)
      assert fixed =~ "_x"
    end
  end

  describe "to_issue/1" do
    test "builds issue with correct rule and line" do
      diag = %{
        severity: :warning,
        message: ~s(variable "foo" is unused),
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

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "_current"
      refute fixed =~ ~r/[^_]current/
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
  #
  # The diagnostic's column points exactly at the unused binding. The
  # fix MUST use it — a string-replace on the line will pick the first
  # textual occurrence of the variable name, which may be a string key,
  # atom key, function name, or alias that happens to contain those
  # characters earlier on the line. Renaming the wrong one silently
  # mangles unrelated code (and, for pattern keys, breaks runtime
  # matching — the original GitHub report).
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

      fixed = Credence.Semantic.fix(source)

      # The binding gets underscored:
      assert fixed =~ ~s|"destination" => _destination|
      # The string key MUST be preserved — otherwise the live-event
      # payload key has been silently renamed.
      refute fixed =~ ~s|"_destination"|
    end

    test "atom-keyed map, binding matches key" do
      source = """
      defmodule Atomic do
        def get(%{foo: foo}), do: :ok
      end
      """

      fixed = Credence.Semantic.fix(source)

      assert fixed =~ "%{foo: _foo}"
      # The atom key stays `foo:`, not `_foo:`.
      refute fixed =~ "%{_foo:"
    end

    test "function name contains the binding name as a substring" do
      source = """
      defmodule Fns do
        def destination_helper(destination), do: nil
      end
      """

      fixed = Credence.Semantic.fix(source)

      assert fixed =~ "def destination_helper(_destination)"
      # The function name MUST NOT be sliced into `_destination_helper`.
      refute fixed =~ "_destination_helper"
    end

    test "function name ENDS with the binding's letters" do
      # The binding `x` first appears textually inside `index` (last
      # letter). A naive string replace would split `index` → `inde_x`.
      source = """
      defmodule Ending do
        def index(:a, x), do: :ok
        def index(:b, x), do: x
      end
      """

      fixed = Credence.Semantic.fix(source)

      assert fixed =~ "def index(:a, _x), do: :ok"
      refute fixed =~ "inde_x"
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Common destructuring shapes — should fix cleanly with no special
  # cases. These exist to lock in behaviour for everyday patterns and
  # would silently regress if the fix logic was rewritten badly.
  # ════════════════════════════════════════════════════════════════

  describe "common destructuring shapes" do
    test "nested tuple pattern with unused inner element" do
      source = """
      defmodule Nested do
        def f({outer, inner}), do: outer
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "{outer, _inner}"
    end

    test "list cons pattern with unused tail" do
      source = """
      defmodule Lst do
        def f([head | tail]), do: head
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "[head | _tail]"
    end

    test "lambda argument unused" do
      source = """
      defmodule Lam do
        def f(list), do: Enum.map(list, fn x -> 1 end)
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "fn _x -> 1 end"
    end

    test "multi-clause function — only the clause whose arg is unused gets touched" do
      source = """
      defmodule Multi do
        def f(:a, x), do: :ok
        def f(:b, x), do: x
      end
      """

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "def f(:a, _x), do: :ok"
      assert fixed =~ "def f(:b, x), do: x"
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

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "{:ok, _val} -> :ok"
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Multiple unused bindings on a single line.
  #
  # Each diagnostic carries its own column. Applying them in arbitrary
  # order would shift later columns by 1 per `_` insert, so the rule
  # must either (a) sort same-line diagnostics right-to-left within
  # one pass, or (b) lean on the pipeline's re-compile-between-passes
  # to refresh columns.
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

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "{_a, _b} = {1, 2}"
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

      fixed = Credence.Semantic.fix(source)
      assert fixed =~ "{_a, {_b, _c}} = {1, {2, 3}}"
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Negative cases: nothing to fix because the compiler emits no
  # warning. Pinning these protects against rule drift (e.g. a future
  # regex change in `match?/1` accidentally firing on legitimate code).
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
      # `def f(x, x)` binds twice with an equality constraint; both
      # are "used" in the sense that they participate in the match.
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
  #
  # When the diagnostic can't be applied unambiguously, the rule must
  # refuse to mutate the source — silently changing the wrong identifier
  # is far worse than leaving a warning visible.
  # ════════════════════════════════════════════════════════════════

  describe "fix/2 — safety guards" do
    test "no column AND var name appears more than once on the line — skip" do
      # Without column info, the rule can't tell which `foo` is the
      # binding and which is the string key. Refusing to act is the
      # only safe choice.
      source = ~s|  %{"foo" => foo} = params\n|

      diag = %{
        severity: :warning,
        message: ~s(variable "foo" is unused),
        position: 1
      }

      assert UnusedVariable.fix(source, diag) == source
    end

    test "column points past the end of the line — skip" do
      source = "x = 1\n"

      diag = %{
        severity: :warning,
        message: ~s(variable "x" is unused),
        position: {1, 100}
      }

      assert UnusedVariable.fix(source, diag) == source
    end

    test "text at the given column does not start with the var name — skip" do
      # The var `x` exists in the source (at column 5), but the diagnostic
      # claims it's at column 1 — which actually holds `y`. A naive
      # first-match string replace would underscore the wrong `x`;
      # respecting the column means we recognise the drift and skip.
      source = "y = x\n"

      diag = %{
        severity: :warning,
        message: ~s(variable "x" is unused),
        position: {1, 1}
      }

      assert UnusedVariable.fix(source, diag) == source
    end
  end
end
