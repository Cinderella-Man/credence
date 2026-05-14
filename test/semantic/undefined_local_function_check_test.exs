defmodule Credence.Semantic.UndefinedLocalFunctionCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.UndefinedLocalFunction

  defp error(msg), do: %{severity: :error, message: msg, position: {1, 1}}

  defp matches?(name, arity) do
    UndefinedLocalFunction.match?(
      error(
        "undefined function #{name}/#{arity} (expected MyModule to define such a function or for it to be imported, but none are available)"
      )
    )
  end

  # ═══════════════════════════════════════════════════════════════════
  # MATCHES — infinity
  # ═══════════════════════════════════════════════════════════════════

  describe "match?/1 – infinity" do
    test "infinity/0" do
      assert matches?("infinity", 0)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MATCHES — max (Python's polymorphic max)
  # ═══════════════════════════════════════════════════════════════════

  describe "match?/1 – max" do
    test "max/1 (max of a list)" do
      assert matches?("max", 1)
    end

    test "max/3 (max of three values)" do
      assert matches?("max", 3)
    end

    test "max/4 (max of four values)" do
      assert matches?("max", 4)
    end

    test "max/5 (max of five values)" do
      assert matches?("max", 5)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MATCHES — min (Python's polymorphic min)
  # ═══════════════════════════════════════════════════════════════════

  describe "match?/1 – min" do
    test "min/1 (min of a list)" do
      assert matches?("min", 1)
    end

    test "min/3 (min of three values)" do
      assert matches?("min", 3)
    end

    test "min/4 (min of four values)" do
      assert matches?("min", 4)
    end

    test "min/5 (min of five values)" do
      assert matches?("min", 5)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MATCHES — other Python built-ins
  # ═══════════════════════════════════════════════════════════════════

  describe "match?/1 – Python built-ins" do
    test "sum/1 (Python sum(list))" do
      assert matches?("sum", 1)
    end

    test "sorted/1 (Python sorted(list))" do
      assert matches?("sorted", 1)
    end

    test "len/1 (Python len(list))" do
      assert matches?("len", 1)
    end

    test "reversed/1 (Python reversed(list))" do
      assert matches?("reversed", 1)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MATCHES — range (Python's range())
  # ═══════════════════════════════════════════════════════════════════

  describe "match?/1 – range" do
    test "range/1 (Python range(stop))" do
      assert matches?("range", 1)
    end

    test "range/2 (Python range(start, stop))" do
      assert matches?("range", 2)
    end

    test "range/3 (Python range(start, stop, step))" do
      assert matches?("range", 3)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # MATCHES — via FunctionMatcher fallback (unknown functions)
  # ═══════════════════════════════════════════════════════════════════

  describe "match?/1 – matches unknown functions for FunctionMatcher fallback" do
    test "fibonacci/1 (not in replacements, but matches for fallback)" do
      assert matches?("fibonacci", 1)
    end

    test "while/2 (paradigm mismatch, but matches for fallback)" do
      assert matches?("while", 2)
    end

    test "foobar/0 (any undefined local function matches)" do
      assert matches?("foobar", 0)
    end

    test "max/2 (Kernel.max exists but if compiler says undefined, we match)" do
      assert matches?("max", 2)
    end

    test "range/0 (not a Python pattern, but still matches for fallback)" do
      assert matches?("range", 0)
    end

    test "range/4 (not a Python pattern, but still matches for fallback)" do
      assert matches?("range", 4)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REJECTS
  # ═══════════════════════════════════════════════════════════════════

  describe "match?/1 – rejects" do
    test "module-qualified undefined (handled by UndefinedFunction)" do
      refute UndefinedLocalFunction.match?(error("Enum.last/1 is undefined or private"))
    end

    test "warning severity" do
      refute UndefinedLocalFunction.match?(%{
               severity: :warning,
               message:
                 "undefined function infinity/0 (expected MyModule to define such a function)",
               position: {1, 1}
             })
    end

    test "unrelated error" do
      refute UndefinedLocalFunction.match?(error("some other error"))
    end

    test "error without 'undefined function' text" do
      refute UndefinedLocalFunction.match?(error("something went wrong with foo/1"))
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # TO_ISSUE
  # ═══════════════════════════════════════════════════════════════════

  describe "to_issue/1" do
    test "extracts rule and line" do
      issue =
        UndefinedLocalFunction.to_issue(%{
          severity: :error,
          message: "undefined function infinity/0 (expected MyModule to define such a function)",
          position: {19, 76}
        })

      assert issue.rule == :undefined_local_function
      assert issue.meta.line == 19
    end
  end
end
