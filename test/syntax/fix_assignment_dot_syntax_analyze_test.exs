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

    test "flags multiple occurrences across lines" do
      source = """
      a =.foo()
      b =.bar()
      """

      assert [%Issue{meta: %{line: 1}}, %Issue{meta: %{line: 2}}] = analyze(source)
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
end
