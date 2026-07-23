defmodule Credence.Semantic.NoUnreachableCaseClauseByTypeCheckTest do
  use ExUnit.Case

  alias Credence.RuleHelpers
  alias Credence.Semantic.NoUnreachableCaseClauseByType

  # Real message captured from `Code.with_diagnostics` on Elixir 1.20 for a
  # bare `:dt ->` clause matched against `DateTime.compare/2`.
  @real_message """
  the following clause will never match:

      :dt ->

  because it attempts to match on the result of:

      DateTime.compare(a, b)

  which has type:

      dynamic(:eq or :gt or :lt)
  """

  @buggy_source """
  defmodule CredenceUnreachableCaseLiveRepro do
    def sort_order(a, b) do
      case DateTime.compare(a, b) do
        :lt -> :asc
        :gt -> :desc
        :eq -> :same
        :dt -> :unknown
      end
    end
  end
  """

  test "matches the real never-match diagnostic for a bare atom clause" do
    diag = %{severity: :warning, message: @real_message, position: 7}
    assert NoUnreachableCaseClauseByType.match?(diag)
  end

  test "matches the live compiler diagnostic on this Elixir" do
    {:ok, diags} = RuleHelpers.compile_and_capture(@buggy_source)
    assert Enum.any?(diags, &NoUnreachableCaseClauseByType.match?/1)
  end

  test "the semantic phase attributes the live diagnostic to this rule" do
    issues = Credence.Semantic.analyze(@buggy_source)

    assert Enum.any?(issues, &(&1.rule == :no_unreachable_case_clause_by_type))
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUnreachableCaseClauseByType.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: 7}
    refute NoUnreachableCaseClauseByType.match?(diag)
  end

  test "ignores a guarded clause (the deletion does not cover guards)" do
    msg = String.replace(@real_message, ":dt ->", ":dt when x > 0 ->")
    diag = %{severity: :warning, message: msg, position: 7}
    refute NoUnreachableCaseClauseByType.match?(diag)
  end

  test "ignores a non-atom pattern (tuple)" do
    msg = String.replace(@real_message, ":dt ->", "{:dt, _} ->")
    diag = %{severity: :warning, message: msg, position: 7}
    refute NoUnreachableCaseClauseByType.match?(diag)
  end

  test "ignores a non-atom pattern (string)" do
    msg = String.replace(@real_message, ":dt ->", "\"dt\" ->")
    diag = %{severity: :warning, message: msg, position: 7}
    refute NoUnreachableCaseClauseByType.match?(diag)
  end

  test "ignores the pinned-exception clause (handled by FixPinAtomInExceptionCase)" do
    msg = """
    the following clause will never match:

        ^exception ->

    because it attempts to match on the result of:

        e

    which has type:

        %{..., __exception__: term(), __struct__: atom()}
    """

    diag = %{severity: :warning, message: msg, position: 10}
    refute NoUnreachableCaseClauseByType.match?(diag)
  end

  test "ignores the `with` else form (different message, no result-of clause)" do
    msg = """
    the following clause will never match:

        :dt ->

    it is expected to match on type:

        dynamic(:eq or :gt)
    """

    diag = %{severity: :warning, message: msg, position: 7}
    refute NoUnreachableCaseClauseByType.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: 7}

    assert NoUnreachableCaseClauseByType.to_issue(diag).rule ==
             :no_unreachable_case_clause_by_type
  end

  test "preserves the diagnostic message in the issue" do
    diag = %{severity: :warning, message: @real_message, position: 7}
    assert NoUnreachableCaseClauseByType.to_issue(diag).message == @real_message
  end

  test "sets the line in issue meta from a bare integer position" do
    diag = %{severity: :warning, message: @real_message, position: 42}
    assert NoUnreachableCaseClauseByType.to_issue(diag).meta.line == 42
  end

  test "sets the line in issue meta from a tuple position" do
    diag = %{severity: :warning, message: @real_message, position: {42, 7}}
    assert NoUnreachableCaseClauseByType.to_issue(diag).meta.line == 42
  end

  test "should_report? is true when the flagged line carries the dead clause" do
    diag = %{severity: :warning, message: @real_message, position: 7}
    assert NoUnreachableCaseClauseByType.should_report?(diag, @buggy_source)
  end

  test "should_report? is false when the flagged line carries another clause" do
    diag = %{severity: :warning, message: @real_message, position: 4}
    refute NoUnreachableCaseClauseByType.should_report?(diag, @buggy_source)
  end

  test "should_report? is false when deleting would empty the case" do
    source = """
    defmodule CredenceUnreachableCaseOnlyClause do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :dt -> :unknown
        end
      end
    end
    """

    diag = %{severity: :warning, message: @real_message, position: 4}
    refute NoUnreachableCaseClauseByType.should_report?(diag, source)
  end

  test "should_report? is false when two case expressions share the flagged line" do
    source = """
    defmodule CredenceUnreachableCaseAmbiguousLine do
      def f(a, b, c, d) do
        {(case DateTime.compare(a, b) do :eq -> 1; :dt -> 2 end), (case c do :eq -> 1; :dt -> 2 end), d}
      end
    end
    """

    diag = %{severity: :warning, message: @real_message, position: 3}
    refute NoUnreachableCaseClauseByType.should_report?(diag, source)
  end
end
