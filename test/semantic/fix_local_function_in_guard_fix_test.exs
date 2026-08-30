defmodule Credence.Semantic.FixLocalFunctionInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.RuleHelpers
  alias Credence.Semantic.FixLocalFunctionInGuard

  @real_message "cannot find or invoke local is_range/1 inside a guard. Only macros can be invoked inside a guard and they must be defined before their invocation. Called as: is_range(length_range)"

  defp fix(source, message \\ @real_message, line \\ 1) do
    FixLocalFunctionInGuard.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  defp compiles?(source), do: RuleHelpers.compiles?(source)

  test "fixture compilation contains top-level exits" do
    refute compiles?("exit(:boom)")
  end

  test "compiler diagnostic is dispatched and repaired through Semantic" do
    input = """
    defmodule LocalFnGuardDispatchFLFIG do
      defp eligible(x), do: is_integer(x)
      def run(x) when eligible(x), do: x
    end
    """

    expected = """
    defmodule LocalFnGuardDispatchFLFIG do
      defp eligible(x), do: is_integer(x)
      def run(x) when is_integer(x), do: x
    end
    """

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)
    diagnostic = Enum.find(diagnostics, &FixLocalFunctionInGuard.match?/1)
    assert diagnostic
    assert [issue] = Credence.Semantic.analyze(input)
    assert issue.rule == :fix_local_function_in_guard

    actual = Credence.Semantic.fix(input)
    confirm_fix(actual, expected)
    assert {:ok, _actual_diagnostics} = RuleHelpers.compile_and_capture(actual)
    assert {:ok, _control_diagnostics} = RuleHelpers.compile_and_capture(expected)
  end

  test "inlines a zero-argument helper named by the compiler diagnostic" do
    input = """
    defmodule LocalFnGuardZeroFLFIG do
      defp ready(), do: true
      def run(x) when ready(), do: x
    end
    """

    expected = """
    defmodule LocalFnGuardZeroFLFIG do
      defp ready(), do: true
      def run(x) when true, do: x
    end
    """

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)
    diagnostic = Enum.find(diagnostics, &FixLocalFunctionInGuard.match?/1)
    assert diagnostic
    actual = FixLocalFunctionInGuard.fix(input, diagnostic)
    confirm_fix(actual, expected)
    assert {:ok, _actual_diagnostics} = RuleHelpers.compile_and_capture(actual)
    assert {:ok, _control_diagnostics} = RuleHelpers.compile_and_capture(expected)
  end

  test "inlines a multi-argument helper named by the compiler diagnostic" do
    input = """
    defmodule LocalFnGuardMultiFLFIG do
      defp ordered(left, right), do: left <= right
      def run(left, right) when ordered(left, right), do: {left, right}
    end
    """

    expected = """
    defmodule LocalFnGuardMultiFLFIG do
      defp ordered(left, right), do: left <= right
      def run(left, right) when left <= right, do: {left, right}
    end
    """

    assert {:error, diagnostics} = RuleHelpers.compile_and_capture(input)
    diagnostic = Enum.find(diagnostics, &FixLocalFunctionInGuard.match?/1)
    assert diagnostic
    actual = FixLocalFunctionInGuard.fix(input, diagnostic)
    confirm_fix(actual, expected)
    assert {:ok, _actual_diagnostics} = RuleHelpers.compile_and_capture(actual)
    assert {:ok, _control_diagnostics} = RuleHelpers.compile_and_capture(expected)
  end

  test "replaces is_range with is_map in guard" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_integer(x), do: x
      def convert(x) when is_range(x), do: x
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_integer(x), do: x
      def convert(x) when is_map(x), do: x
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed and resolves the compile error" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_range(x), do: x
    end
    """

    refute compiles?(input)
    assert valid_syntax?(fix(input))
    assert compiles?(fix(input))
  end

  test "replaces in multi-guard clauses" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_range(x) when is_integer(x), do: x
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_map(x) when is_integer(x), do: x
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "replaces in case clause guards" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) do
        case x do
          y when is_range(y) -> y
          _ -> nil
        end
      end
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) do
        case x do
          y when is_map(y) -> y
          _ -> nil
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves a variable named is_range untouched while fixing the real call" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_range(x), do: x
      def sum(is_range) when is_integer(is_range), do: is_range
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_map(x), do: x
      def sum(is_range) when is_integer(is_range), do: is_range
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "leaves non-guard is_range calls untouched" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_range(x), do: x
      def describe(x), do: is_range(x)
    end
    """

    expected = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x) when is_map(x), do: x
      def describe(x), do: is_range(x)
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "no-op when the helper is not an is_map alias" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_struct(x, Range)

      def convert(x) when is_range(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the helper has multiple clauses" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(%Range{}), do: true
      defp is_range(_), do: false

      def convert(x) when is_range(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when the helper clause is guarded" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x) when is_map(x), do: is_map(x)

      def convert(x) when is_range(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op when no local is_range/1 is defined" do
    input = """
    defmodule LocalFnInGuard do
      def convert(x) when is_range(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "no-op on a two-argument is_range call in a guard" do
    input = """
    defmodule LocalFnInGuard do
      defp is_range(x), do: is_map(x)

      def convert(x, y) when is_range(x, y), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged when no is_range present" do
    input = """
    defmodule CleanExample do
      def convert(x) when is_map(x), do: x
    end
    """

    confirm_fix(fix(input), input)
  end

  test "returns source unchanged for unrelated code" do
    input = """
    defmodule CleanExample do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not borrow a helper from another module" do
    input = """
    defmodule LocalFnGuardOwnerFLFIG do
      defp allowed(x), do: is_integer(x)
    end

    defmodule LocalFnGuardCallerFLFIG do
      def run(x) when allowed(x), do: x
    end
    """

    confirm_fix(
      fix(input, "cannot find or invoke local allowed/1 inside a guard", 6),
      input
    )
  end

  test "rewrites only the diagnosed module and leaves quoted guards untouched" do
    input = """
    defmodule LocalFnGuardQuoteFLFIG do
      defp allowed(x), do: is_integer(x)
      def run(x) when allowed(x), do: x

      def generated do
        quote do
          def run(x) when allowed(x), do: x
        end
      end
    end
    """

    expected = """
    defmodule LocalFnGuardQuoteFLFIG do
      defp allowed(x), do: is_integer(x)
      def run(x) when is_integer(x), do: x

      def generated do
        quote do
          def run(x) when allowed(x), do: x
        end
      end
    end
    """

    confirm_fix(
      fix(input, "cannot find or invoke local allowed/1 inside a guard", 3),
      expected
    )
  end

  test "declines when a guard-safe name resolves to a local function" do
    input = """
    defmodule LocalFnGuardShadowFLFIG do
      import Kernel, except: [is_map: 1]
      defp is_map(_x), do: false
      defp eligible(x), do: is_map(x)
      def run(x) when eligible(x), do: x
    end
    """

    fixed = fix(input, "cannot find or invoke local eligible/1 inside a guard", 5)

    confirm_fix(fixed, input)
    assert {:error, input_diagnostics} = Credence.RuleHelpers.compile_and_capture(input)

    assert Enum.any?(
             input_diagnostics,
             &(&1.message ==
                 "cannot find or invoke local eligible/1 inside a guard. Only macros can be invoked inside a guard and they must be defined before their invocation. Called as: eligible(x)")
           )
  end
end
