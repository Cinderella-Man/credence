defmodule Credence.Semantic.NoUnreachableCatchAfterRescueCheckTest do
  use ExUnit.Case

  alias Credence.RuleHelpers
  alias Credence.Semantic.NoUnreachableCatchAfterRescue

  # Real message captured from `Code.with_diagnostics` on this Elixir for the
  # `catch :error, reason ->` clause of `@buggy_source` (line 8), shadowed by
  # the `rescue e ->` catch-all on line 6.
  @real_message "this clause cannot match because a previous clause at line 6 matches the same pattern as this clause"

  @buggy_source """
  defmodule CredenceUnreachableCatchLiveRepro do
    def run(f) do
      try do
        f.()
      rescue
        e -> {:error, e}
      catch
        :error, reason -> {:error, reason}
      end
    end
  end
  """

  test "matches the real cannot-match diagnostic" do
    diag = %{severity: :warning, message: @real_message, position: {8, 22}}
    assert NoUnreachableCatchAfterRescue.match?(diag)
  end

  test "matches the live compiler diagnostic on this Elixir" do
    {:ok, diags} = RuleHelpers.compile_and_capture(@buggy_source)
    assert Enum.any?(diags, &NoUnreachableCatchAfterRescue.match?/1)
  end

  test "the semantic phase attributes the live diagnostic to this rule" do
    issues = Credence.Semantic.analyze(@buggy_source)

    assert Enum.any?(issues, &(&1.rule == :no_unreachable_catch_after_rescue))
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute NoUnreachableCatchAfterRescue.match?(diag)
  end

  test "ignores the always-matches variant of the warning" do
    msg = "this clause cannot match because a previous clause at line 6 always matches"
    diag = %{severity: :warning, message: msg, position: {8, 22}}
    refute NoUnreachableCatchAfterRescue.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {8, 22}}
    refute NoUnreachableCatchAfterRescue.match?(diag)
  end

  test "attributes the issue to this rule" do
    diag = %{severity: :warning, message: @real_message, position: {8, 22}}

    assert NoUnreachableCatchAfterRescue.to_issue(diag).rule ==
             :no_unreachable_catch_after_rescue
  end

  test "preserves the diagnostic message in the issue" do
    diag = %{severity: :warning, message: @real_message, position: {8, 22}}
    assert NoUnreachableCatchAfterRescue.to_issue(diag).message == @real_message
  end

  test "sets the line in issue meta from a tuple position" do
    diag = %{severity: :warning, message: @real_message, position: {8, 22}}
    assert NoUnreachableCatchAfterRescue.to_issue(diag).meta.line == 8
  end

  test "sets the line in issue meta from a bare integer position" do
    diag = %{severity: :warning, message: @real_message, position: 8}
    assert NoUnreachableCatchAfterRescue.to_issue(diag).meta.line == 8
  end

  test "should_report? is true when the flagged line carries the dead clause" do
    diag = %{severity: :warning, message: @real_message, position: {8, 22}}
    assert NoUnreachableCatchAfterRescue.should_report?(diag, @buggy_source)
  end

  test "should_report? is false when the flagged line carries another clause" do
    diag = %{severity: :warning, message: @real_message, position: {6, 9}}
    refute NoUnreachableCatchAfterRescue.should_report?(diag, @buggy_source)
  end

  # No issue: `rescue e in RuntimeError ->` narrows to one exception type, so a
  # `catch :error, reason ->` clause after it is still reachable.
  test "no issue when the rescue clause is not a catch-all" do
    source = """
    defmodule CredenceUnreachableCatchNarrowRescue do
      def run(f) do
        try do
          f.()
        rescue
          e in RuntimeError -> {:error, e}
        catch
          :error, reason -> {:error, reason}
        end
      end
    end
    """

    diag = %{severity: :warning, message: @real_message, position: {8, 22}}
    refute NoUnreachableCatchAfterRescue.should_report?(diag, source)

    {:ok, diags} = RuleHelpers.compile_and_capture(source)
    refute Enum.any?(diags, &NoUnreachableCatchAfterRescue.match?/1)
  end

  # No issue: a single-pattern `catch :error ->` catches `throw(:error)`, which
  # a rescue catch-all does not shadow. The compiler does not warn about it and
  # neither do we — deleting it would drop live code.
  test "no issue for a single-pattern catch :error -> (a throw clause)" do
    source = """
    defmodule CredenceUnreachableCatchThrowClause do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        catch
          :error -> :caught_throw
        end
      end
    end
    """

    diag = %{severity: :warning, message: @real_message, position: {8, 14}}
    refute NoUnreachableCatchAfterRescue.should_report?(diag, source)

    {:ok, diags} = RuleHelpers.compile_and_capture(source)
    refute Enum.any?(diags, &NoUnreachableCatchAfterRescue.match?/1)
  end

  # No issue: `:exit` / `:throw` clauses catch a different kind, so a rescue
  # catch-all never shadows them.
  test "no issue for an :exit catch clause" do
    source = """
    defmodule CredenceUnreachableCatchExitClause do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        catch
          :exit, reason -> {:exit, reason}
        end
      end
    end
    """

    diag = %{severity: :warning, message: @real_message, position: {8, 21}}
    refute NoUnreachableCatchAfterRescue.should_report?(diag, source)

    {:ok, diags} = RuleHelpers.compile_and_capture(source)
    refute Enum.any?(diags, &NoUnreachableCatchAfterRescue.match?/1)
  end

  # Deliberately skipped: the compiler *does* flag a guarded clause here, but
  # the deletion is kept to the plain two-pattern shape.
  test "no issue for a guarded catch clause even though the compiler flags it" do
    source = """
    defmodule CredenceUnreachableCatchGuardedClause do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:error, e}
        catch
          :error, reason when is_atom(reason) -> {:error, reason}
        end
      end
    end
    """

    {:ok, diags} = RuleHelpers.compile_and_capture(source)
    assert Enum.any?(diags, &NoUnreachableCatchAfterRescue.match?/1)

    refute Enum.any?(
             Credence.Semantic.analyze(source),
             &(&1.rule == :no_unreachable_catch_after_rescue)
           )
  end

  # Deliberately skipped: the warning is generic, so a duplicate `case` clause
  # emits it too. `should_report?/2` keeps it out of this rule's issues.
  test "no issue for a duplicate case clause carrying the same warning" do
    source = """
    defmodule CredenceUnreachableCatchDuplicateCase do
      def run(x) do
        case x do
          :a -> 1
          :a -> 2
          _ -> 3
        end
      end
    end
    """

    {:ok, diags} = RuleHelpers.compile_and_capture(source)
    assert Enum.any?(diags, &NoUnreachableCatchAfterRescue.match?/1)

    refute Enum.any?(
             Credence.Semantic.analyze(source),
             &(&1.rule == :no_unreachable_catch_after_rescue)
           )
  end

  # No issue: two `try` blocks share the flagged line, so only one of the two
  # candidate clauses is the dead one — the rule declines rather than guess.
  test "no issue when two candidate clauses share the flagged line" do
    source = """
    defmodule CredenceUnreachableCatchAmbiguousLine do
      def run(f, g) do
        x = 1
        y = 2
        {(try do f.() rescue e -> {:e, e} catch :error, r -> {:c, r} end), (try do g.() rescue e -> {:e, e} catch :error, r -> {:c, r} end), x, y}
      end
    end
    """

    msg =
      "this clause cannot match because a previous clause at line 5 matches the same pattern as this clause"

    diag = %{severity: :warning, message: msg, position: {5, 55}}
    refute NoUnreachableCatchAfterRescue.should_report?(diag, source)
  end
end
