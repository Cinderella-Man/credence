defmodule Credence.Syntax.FixForComprehensionInKeywordValueFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixForComprehensionInKeywordValue

  defp analyze(code), do: FixForComprehensionInKeywordValue.analyze(code)
  defp fix(code), do: FixForComprehensionInKeywordValue.fix(code)

  test "fixes a single for comprehension in a map keyword value" do
    input = "%{foo: for x <- [1,2,3], into: %{}, do: {x, x}}"
    expected = "%{foo: (for x <- [1,2,3], into: %{}, do: {x, x})}"
    confirm_fix(fix(input), expected)
  end

  test "fixes multiple for comprehensions in nested map keyword values" do
    input = """
    defmodule M do
      def build_metrics(final_metrics) do
        %{
          metrics: %{
            processed: for {id, {p, _, _}} <- final_metrics, into: %{}, do: {id, p},
            steals: for {id, {_, s, _}} <- final_metrics, into: %{}, do: {id, s},
            stolen: for {id, {_, _, st}} <- final_metrics, into: %{}, do: {id, st}
          }
        }
      end
    end
    """

    expected = """
    defmodule M do
      def build_metrics(final_metrics) do
        %{
          metrics: %{
            processed: (for {id, {p, _, _}} <- final_metrics, into: %{}, do: {id, p}),
            steals: (for {id, {_, s, _}} <- final_metrics, into: %{}, do: {id, s}),
            stolen: (for {id, {_, _, st}} <- final_metrics, into: %{}, do: {id, st})
          }
        }
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    code = "%{foo: for x <- [1,2,3], into: %{}, do: {x, x}}"
    assert analyze(fix(code)) == []
  end

  test "fixed output is well-formed (parses)" do
    code = "%{foo: for x <- [1,2,3], into: %{}, do: {x, x}}"
    assert valid_syntax?(fix(code))
  end

  test "does not modify already-parenthesized for comprehension" do
    code = "%{foo: (for x <- [1,2,3], into: %{}, do: {x, x})}"
    confirm_fix(fix(code), code)
  end

  test "does not modify valid code without for" do
    code = "%{foo: 1 + 2}"
    confirm_fix(fix(code), code)
  end
end
