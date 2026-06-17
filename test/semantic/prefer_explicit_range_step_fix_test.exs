defmodule Credence.Semantic.PreferExplicitRangeStepFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.PreferExplicitRangeStep

  # The range-step deprecation carries no usable position (always `0`), so the
  # fix ignores it and rewrites the source by AST. The message only gates that
  # this is our diagnostic; its exact text does not steer the rewrite.
  defp fix(source, range \\ "1..-2") do
    msg = "#{range} has a default step of -1, please write #{range}//-1 instead"
    PreferExplicitRangeStep.fix(source, %{severity: :warning, message: msg, position: 0})
  end

  test "appends the explicit step to a descending literal range" do
    confirm_fix(
      fix("Enum.slice(list, 1..-2)"),
      "Enum.slice(list, 1..-2//-1)"
    )
  end

  test "handles a descending all-positive literal range" do
    confirm_fix(
      fix("for i <- 5..1, do: i"),
      "for i <- 5..1//-1, do: i"
    )
  end

  test "handles two negative literal endpoints" do
    confirm_fix(
      fix("Enum.take(l, -1..-5)"),
      "Enum.take(l, -1..-5//-1)"
    )
  end

  test "fixed output parses" do
    assert valid_syntax?(fix("Enum.slice(list, 10..-5)"))
  end

  test "rewrites every descending range in the source" do
    confirm_fix(
      fix("{Enum.take(a, 1..-2), Enum.take(b, 5..1)}"),
      "{Enum.take(a, 1..-2//-1), Enum.take(b, 5..1//-1)}"
    )
  end

  test "rewrites a spaced range the message would have normalized away" do
    confirm_fix(
      fix("Enum.slice(list, 1 .. -2)"),
      "Enum.slice(list, 1 .. -2//-1)"
    )
  end

  # Behaviour-safety: text that merely *looks* like the range must be left
  # alone — only genuine `..` operator nodes are patched.

  test "never rewrites the same digits inside a string literal" do
    confirm_fix(
      fix(~S'{Enum.slice(l, 1..-2), "label 1..-2"}'),
      ~S'{Enum.slice(l, 1..-2//-1), "label 1..-2"}'
    )
  end

  test "never rewrites the same digits inside an atom" do
    confirm_fix(
      fix(~S'{Enum.slice(l, 1..-2), :"k1..-2"}'),
      ~S'{Enum.slice(l, 1..-2//-1), :"k1..-2"}'
    )
  end

  # Boundary safety: an ascending range and an already-stepped range are not
  # descending-literal `..` nodes, so they are untouched.

  test "leaves an ascending literal range alone" do
    confirm_fix(fix("Enum.slice(l, 1..2)"), "Enum.slice(l, 1..2)")
  end

  test "leaves an equal-endpoint range alone" do
    confirm_fix(fix("Enum.slice(l, 3..3)"), "Enum.slice(l, 3..3)")
  end

  test "is idempotent on an already-stepped range" do
    confirm_fix(fix("Enum.slice(list, 1..-2//-1)"), "Enum.slice(list, 1..-2//-1)")
  end

  test "leaves a range with a variable endpoint alone" do
    confirm_fix(fix("Enum.slice(l, a..-1)"), "Enum.slice(l, a..-1)")
  end

  test "leaves source unchanged on a malformed message" do
    src = "Enum.slice(list, 1..-2)"
    out = PreferExplicitRangeStep.fix(src, %{severity: :warning, message: "garbage", position: 0})
    confirm_fix(out, src)
  end

  test "leaves unparseable source unchanged" do
    src = "Enum.slice(list, 1..-2"
    confirm_fix(fix(src), src)
  end

  # End-to-end through the real semantic phase: the rule must be discovered and
  # produce the explicit-step form (which resolves the deprecation) while
  # leaving a same-text string literal untouched. The stepped output pinned here
  # is exactly the source the compiler stops warning about.
  test "resolves the deprecation via the full semantic pipeline" do
    src = """
    defmodule PreferExplicitRangeStepPipelineFixture do
      def f(l), do: {Enum.slice(l, 1..-2), "label 1..-2"}
      def g(l), do: Enum.take(l, 5..1)
    end
    """

    expected = """
    defmodule PreferExplicitRangeStepPipelineFixture do
      def f(l), do: {Enum.slice(l, 1..-2//-1), "label 1..-2"}
      def g(l), do: Enum.take(l, 5..1//-1)
    end
    """

    confirm_fix(Credence.Semantic.fix(src), expected)
  end
end
