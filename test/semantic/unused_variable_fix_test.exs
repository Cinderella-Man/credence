defmodule Credence.Semantic.UnusedVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.UnusedVariable

  # ── Unit tests (rule logic with synthetic diagnostics) ──────────

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

      confirm_fix(UnusedVariable.fix(source, diag), expected)
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
      confirm_fix(UnusedVariable.fix(source, diag), source)
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

      confirm_fix(UnusedVariable.fix(source, diag), expected)
    end

    test "handles position as bare integer" do
      source = "x = 1"

      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: 1
      }

      confirm_fix(UnusedVariable.fix(source, diag), "_x = 1")
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Collision: a plain `_` prefix would collide with an existing
  # underscored binding on the same line. An underscored name repeated
  # in a pattern still binds, so `{_ref, _ref}` would only match equal
  # pairs — a different answer. Rename with a numeric suffix instead.
  # ════════════════════════════════════════════════════════════════

  describe "fix/2 — underscore-name collisions" do
    test "collision: _var already on line → appends numeric suffix" do
      source = "fn {_ref, {pid, ref, task_ref}} -> is_nil(task_ref) end"

      diag = %{
        severity: :warning,
        message: """
        variable "ref" is unused
        """,
        position: {1, 17}
      }

      expected = "fn {_ref, {pid, _ref_1, task_ref}} -> is_nil(task_ref) end"
      confirm_fix(UnusedVariable.fix(source, diag), expected)
    end

    test "collision: _var_1 already on line → appends _var_2" do
      source = "fn {_ref, {_ref_1, ref}} -> :ok end"

      diag = %{
        severity: :warning,
        message: """
        variable "ref" is unused
        """,
        position: {1, 20}
      }

      expected = "fn {_ref, {_ref_1, _ref_2}} -> :ok end"
      confirm_fix(UnusedVariable.fix(source, diag), expected)
    end

    test "no collision: _var not on line → simple underscore prefix" do
      source = "fn {ref, task_ref} -> is_nil(task_ref) end"

      diag = %{
        severity: :warning,
        message: """
        variable "ref" is unused
        """,
        position: {1, 5}
      }

      expected = "fn {_ref, task_ref} -> is_nil(task_ref) end"
      confirm_fix(UnusedVariable.fix(source, diag), expected)
    end

    test "collision detection ignores substring look-alikes" do
      source = "fn {_reference, ref} -> :ok end"

      diag = %{
        severity: :warning,
        message: """
        variable "ref" is unused
        """,
        position: {1, 17}
      }

      # `_reference` merely contains "_ref"; it is not a standalone `_ref`,
      # so the plain prefix is still free.
      expected = "fn {_reference, _ref} -> :ok end"
      confirm_fix(UnusedVariable.fix(source, diag), expected)
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Deliberately unhandled: "the underscored variable ... appears more
  # than once in a match". check/1 stays silent on it (see the check
  # test), and fix/2 is a no-op — the two agree.
  # ════════════════════════════════════════════════════════════════

  describe "fix/2 — repeated underscored variable is left alone" do
    test "fix/2 is a no-op on the verbatim compiler diagnostic" do
      source = "fn {_ref, {_pid, _ref, task_ref}} -> nil end"

      diag = %{
        severity: :warning,
        message:
          "the underscored variable \"_ref\" appears more than once in a match. " <>
            "This means the pattern will only match if all \"_ref\" bind to the same value. " <>
            "If this is the intended behaviour, please remove the leading underscore from the " <>
            "variable name, otherwise give the variables different names",
        position: {1, 18},
        file: "credence_check.ex",
        source: "credence_check.ex"
      }

      confirm_fix(UnusedVariable.fix(source, diag), source)
    end

    test "end-to-end fix leaves a repeated underscored pattern untouched" do
      source = """
      defmodule RepeatedUnderscoreFix do
        def f({_ref, _ref}), do: :ok
        def f(_), do: :other
      end
      """

      confirm_fix(Credence.Semantic.fix(source), source)
    end
  end

  # ── Integration tests (through Credence.Semantic coordinator) ───

  describe "integration through Credence.Semantic" do
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

      confirm_fix(Credence.Semantic.fix(source), expected)
    end

    test "collision: renames ref to _ref_1 when _ref already exists in pattern" do
      source = """
      defmodule CollisionInteg do
        def f({_ref, ref}), do: :ok
      end
      """

      expected = """
      defmodule CollisionInteg do
        def f({_ref, _ref_1}), do: :ok
      end
      """

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
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

      confirm_fix(Credence.Semantic.fix(source), expected)
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Safety guards on `fix/2`.
  # ════════════════════════════════════════════════════════════════

  describe "fix/2 — safety guards" do
    test "no column AND var name appears more than once on the line — skip" do
      source = ~S'  %{"foo" => foo} = params'

      diag = %{
        severity: :warning,
        message: """
        variable "foo" is unused
        """,
        position: 1
      }

      confirm_fix(UnusedVariable.fix(source, diag), source)
    end

    test "column points past the end of the line — skip" do
      source = "x = 1"

      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: {1, 100}
      }

      confirm_fix(UnusedVariable.fix(source, diag), source)
    end

    test "text at the given column does not start with the var name — skip" do
      source = "y = x"

      diag = %{
        severity: :warning,
        message: """
        variable "x" is unused
        """,
        position: {1, 1}
      }

      confirm_fix(UnusedVariable.fix(source, diag), source)
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
