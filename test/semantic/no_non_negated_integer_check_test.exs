defmodule Credence.Semantic.NoNonNegatedIntegerCheckTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2]

  alias Credence.Semantic.NoNonNegatedInteger

  @diagnostic %{
    message:
      "credence_check.ex:5: type non_negated_integer/0 undefined (no such type in Solution)",
    position: 5,
    file: "credence_check.ex",
    severity: :error
  }

  test "matches the diagnostic" do
    assert NoNonNegatedInteger.match?(@diagnostic)
  end

  # NoBareNamesInSpec also matches `type non_negated_integer/0 undefined`
  # (its `type _/0 undefined` regex) but cannot fix the parenthesised type
  # call, so this rule must out-rank it or it would be dead in production.
  test "wins the diagnostic over NoBareNamesInSpec and resolves the error end-to-end" do
    src = """
    defmodule Solution do
      @spec power_of_num(number(), non_negated_integer()) :: number()
      def power_of_num(_base, 0), do: 1
      def power_of_num(base, e) when is_integer(e) and e > 0, do: base * power_of_num(base, e - 1)
    end
    """

    expected = """
    defmodule Solution do
      @spec power_of_num(number(), non_neg_integer()) :: number()
      def power_of_num(_base, 0), do: 1
      def power_of_num(base, e) when is_integer(e) and e > 0, do: base * power_of_num(base, e - 1)
    end
    """

    rules = Credence.Semantic.default_rules()
    {:error, diags} = Credence.RuleHelpers.compile_and_capture(src)

    winner = Enum.find(rules, fn r -> Enum.any?(diags, &r.match?/1) end)
    assert winner == NoNonNegatedInteger

    confirm_fix(Credence.Semantic.fix(src), expected)
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoNonNegatedInteger.match?(diag)
  end

  test "ignores warnings" do
    diag = %{
      severity: :warning,
      message: "type non_negated_integer/0 undefined",
      position: {1, 1}
    }

    refute NoNonNegatedInteger.match?(diag)
  end

  test "attributes the issue to this rule" do
    assert NoNonNegatedInteger.to_issue(@diagnostic).rule == :no_non_negated_integer
  end

  test "preserves the diagnostic message" do
    assert NoNonNegatedInteger.to_issue(@diagnostic).message == @diagnostic.message
  end

  test "extracts line from integer position" do
    issue = NoNonNegatedInteger.to_issue(@diagnostic)
    assert issue.meta.line == 5
  end

  test "extracts line from tuple position" do
    diag = %{severity: :error, message: "type non_negated_integer/0 undefined", position: {3, 7}}
    issue = NoNonNegatedInteger.to_issue(diag)
    assert issue.meta.line == 3
  end
end
