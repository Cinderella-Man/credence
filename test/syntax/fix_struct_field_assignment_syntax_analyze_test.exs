defmodule Credence.Syntax.FixStructFieldAssignmentSyntaxAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixStructFieldAssignmentSyntax

  defp analyze(code), do: FixStructFieldAssignmentSyntax.analyze(code)

  describe "analyze/1 — flags the unparseable code" do
    test "flags `left.right = node`" do
      assert [%Issue{rule: :fix_struct_field_assignment_syntax, meta: %{line: 1}}] =
               analyze("left.right = node")
    end

    test "flags `node.left = left_right`" do
      assert [%Issue{rule: :fix_struct_field_assignment_syntax, meta: %{line: 1}}] =
               analyze("node.left = left_right")
    end

    test "flags inside a full module" do
      source = """
      defmodule RotateTest do
        defp rotate_right(node) do
          left = node.left
          left_right = left.right

          left.right = node
          node.left = left_right

          left
        end
      end
      """

      assert [
               %Issue{rule: :fix_struct_field_assignment_syntax, meta: %{line: 6}},
               %Issue{rule: :fix_struct_field_assignment_syntax, meta: %{line: 7}}
             ] = analyze(source)
    end

    test "flags multiple occurrences across lines" do
      source = """
      a.x = 1
      b.y = 2
      """

      assert [%Issue{meta: %{line: 1}}, %Issue{meta: %{line: 2}}] = analyze(source)
    end
  end

  describe "analyze/1 — leaves good code alone" do
    test "map update syntax" do
      assert analyze("%{left | right: node}") == []
    end

    test "comparison operators" do
      assert analyze("a == b") == []
      assert analyze("a === b") == []
      assert analyze("a >= b") == []
      assert analyze("a <= b") == []
      assert analyze("a != b") == []
      assert analyze("a =~ b") == []
    end

    test "plain field access without assignment" do
      assert analyze("left.right") == []
    end

    test "normal variable assignment" do
      assert analyze("left = node") == []
    end

    test "comment line is not flagged" do
      assert analyze("# left.right = node") == []
    end

    test "function call" do
      assert analyze("Map.put(left, :right, node)") == []
    end
  end
end
