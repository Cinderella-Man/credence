defmodule Credence.Syntax.FixStructFieldAssignmentSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixStructFieldAssignmentSyntax

  defp analyze(code), do: FixStructFieldAssignmentSyntax.analyze(code)
  defp fix(code), do: FixStructFieldAssignmentSyntax.fix(code)

  describe "fix/1 — rewrites field assignment to map update" do
    test "fixes `left.right = node` to `left = %{left | right: node}`" do
      confirm_fix(fix("left.right = node"), "left = %{left | right: node}")
    end

    test "fixes `node.left = left_right`" do
      confirm_fix(fix("node.left = left_right"), "node = %{node | left: left_right}")
    end

    test "fixes inside a full module" do
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

      expected = """
      defmodule RotateTest do
        defp rotate_right(node) do
          left = node.left
          left_right = left.right

          left = %{left | right: node}
          node = %{node | left: left_right}

          left
        end
      end
      """

      confirm_fix(fix(source), expected)
    end

    test "fixes multiple occurrences" do
      source = """
      a.x = 1
      b.y = 2
      """

      expected = """
      a = %{a | x: 1}
      b = %{b | y: 2}
      """

      confirm_fix(fix(source), expected)
    end

    test "preserves indentation" do
      confirm_fix(fix("    left.right = node"), "    left = %{left | right: node}")
    end
  end

  describe "fix/1 — no-ops on valid code" do
    test "map update unchanged" do
      code = "%{left | right: node}"
      confirm_fix(fix(code), code)
    end

    test "comparison unchanged" do
      code = "a == b"
      confirm_fix(fix(code), code)
    end

    test "comment line unchanged" do
      code = "# left.right = node"
      confirm_fix(fix(code), code)
    end
  end

  describe "round-trip" do
    test "fixed output no longer flags" do
      assert analyze(fix("left.right = node")) == []
    end

    test "fixed output is well-formed (parses)" do
      assert valid_syntax?(fix("left.right = node"))
    end

    test "full module round-trip" do
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

      fixed = fix(source)
      assert valid_syntax?(fixed)
      assert analyze(fixed) == []
    end
  end
end
