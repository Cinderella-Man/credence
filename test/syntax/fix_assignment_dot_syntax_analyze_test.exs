defmodule Credence.Syntax.FixAssignmentDotSyntaxAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixAssignmentDotSyntax

  defp analyze(code), do: FixAssignmentDotSyntax.analyze(code)

  describe "analyze/1 — flags the extra dot after =" do
    test "flags `ref =.make_ref()`" do
      assert [%Issue{rule: :fix_assignment_dot_syntax, meta: %{line: 1}}] =
               analyze("ref =.make_ref()")
    end

    test "flags with space before dot: `ref = .make_ref()`" do
      assert [%Issue{rule: :fix_assignment_dot_syntax}] = analyze("ref = .make_ref()")
    end

    test "flags inside a defmodule" do
      source = """
      defmodule Example do
        def make_ref_example do
          ref =.make_ref()
          ref
        end
      end
      """

      assert [%Issue{rule: :fix_assignment_dot_syntax, meta: %{line: 3}}] = analyze(source)
    end

    test "flags a qualified call: `x =.Module.fun()`" do
      assert [%Issue{rule: :fix_assignment_dot_syntax}] = analyze("x =.Module.fun()")
    end

    test "flags multiple occurrences across lines" do
      source = """
      a =.foo()
      b =.bar()
      """

      assert [%Issue{meta: %{line: 1}}, %Issue{meta: %{line: 2}}] = analyze(source)
    end
  end

  describe "analyze/1 — a non-ASCII variable name" do
    # `café = make_ref()` is valid Elixir, so `café =.make_ref()` is the same
    # syntax error as `ref =.make_ref()` and gets the same issue.
    test "flags `café =.make_ref()`" do
      assert [%Issue{rule: :fix_assignment_dot_syntax, meta: %{line: 1}}] =
               analyze("café =.make_ref()")
    end

    test "flags one with a non-ASCII byte after the first character" do
      assert [%Issue{rule: :fix_assignment_dot_syntax}] = analyze("größe =.byte_size(x)")
    end
  end

  describe "analyze/1 — leaves good code alone" do
    test "valid assignment without extra dot" do
      assert analyze("ref = make_ref()") == []
    end

    test "plain variable assignment" do
      assert analyze("x = 1") == []
    end

    test "comparison operators" do
      assert analyze("a == b") == []
      assert analyze("a >= b") == []
      assert analyze("a <= b") == []
    end

    test "match operator with map" do
      assert analyze("%{a: 1} = expr") == []
    end

    test "comment line is not flagged" do
      assert analyze("# ref =.make_ref()") == []
    end
  end

  describe "analyze/1 — deliberately skipped: a digit after the dot" do
    # `.5` after `=` reads as a Python float literal, not as a spurious dot
    # before a call. Removing the dot would change the value (`rate = .05` ->
    # `rate = 05`, the integer 5) or break the parse (`x =.5e3` -> `x = 5e3`),
    # so the rule stays out of it entirely — no issue, no fix.
    test "python float literal with a space" do
      assert analyze("rate = .05") == []
    end

    test "python float literal without a space" do
      assert analyze("x =.5") == []
    end

    test "python float literal in scientific notation" do
      assert analyze("x =.5e3") == []
    end
  end

  describe "analyze/1 — other shapes the fix does not handle" do
    test "anonymous call syntax is not flagged" do
      assert analyze("f =.(1)") == []
    end

    test "second `=` on the line is not flagged" do
      assert analyze("x = y =.foo()") == []
    end

    test "trailing comment containing the bad shape is not flagged" do
      assert analyze("x = 1 # ref =.make_ref()") == []
    end

    test "non-identifier left-hand side is not flagged" do
      assert analyze("@attr =.foo()") == []
    end
  end
end
