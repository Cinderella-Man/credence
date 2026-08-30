defmodule Credence.Semantic.PreferRescueBeforeCatchCheckTest do
  use ExUnit.Case

  alias Credence.RuleHelpers
  alias Credence.Semantic.PreferRescueBeforeCatch

  # Real message captured from `Code.with_diagnostics` on this Elixir for
  # `@buggy_source` — the position points at the `try` keyword.
  @real_message "\"catch\" should always come after \"rescue\" in try"

  @buggy_source """
  defmodule CredenceRescueOrderLiveRepro do
    def run(f) do
      try do
        f.()
      catch
        :exit, reason -> {:exit, reason}
        :throw, value -> {:throw, value}
      rescue
        e -> {:rescue, e}
      end
    end
  end
  """

  @diagnostic %{severity: :warning, message: @real_message, position: {3, 5}}

  test "matches the real ordering diagnostic" do
    assert PreferRescueBeforeCatch.match?(@diagnostic)
  end

  test "matches the live compiler diagnostic on this Elixir" do
    {:ok, diags} = RuleHelpers.compile_and_capture(@buggy_source)
    assert Enum.any?(diags, &PreferRescueBeforeCatch.match?/1)
  end

  test "the semantic phase attributes the live diagnostic to this rule" do
    issues = Credence.Semantic.analyze(@buggy_source)

    assert Enum.any?(issues, &(&1.rule == :prefer_rescue_before_catch))
  end

  test "ignores unrelated diagnostics" do
    diag = %{severity: :warning, message: "unrelated", position: {1, 1}}
    refute PreferRescueBeforeCatch.match?(diag)
  end

  test "ignores error severity" do
    diag = %{severity: :error, message: @real_message, position: {3, 5}}
    refute PreferRescueBeforeCatch.match?(diag)
  end

  test "ignores a non-binary message" do
    refute PreferRescueBeforeCatch.match?(%{severity: :warning, message: nil, position: 1})
  end

  test "attributes the issue to this rule" do
    assert PreferRescueBeforeCatch.to_issue(@diagnostic).rule == :prefer_rescue_before_catch
  end

  test "preserves the diagnostic message in the issue" do
    assert PreferRescueBeforeCatch.to_issue(@diagnostic).message == @real_message
  end

  test "sets the line in issue meta from a tuple position" do
    assert PreferRescueBeforeCatch.to_issue(@diagnostic).meta.line == 3
  end

  test "sets the line in issue meta from a bare integer position" do
    diag = %{severity: :warning, message: @real_message, position: 3}
    assert PreferRescueBeforeCatch.to_issue(diag).meta.line == 3
  end

  test "sets a nil line when the position has an unexpected shape" do
    diag = %{severity: :warning, message: @real_message, position: nil}
    assert PreferRescueBeforeCatch.to_issue(diag).meta.line == nil
  end

  test "should_report? is true when the source holds an out-of-order try" do
    assert PreferRescueBeforeCatch.should_report?(@diagnostic, @buggy_source)
  end

  # No issue: the compiler emits a *different* message for a `def` body with the
  # same mistake (`… in def`, not `… in try`), and the fix only rewrites literal
  # `try` blocks. Both halves decline, so check and fix agree.
  test "no issue for the same mistake in a def body" do
    source = """
    defmodule CredenceRescueOrderDefBody do
      def run(f) do
        f.()
      catch
        :exit, reason -> {:exit, reason}
      rescue
        e -> {:rescue, e}
      end
    end
    """

    {:ok, diags} = RuleHelpers.compile_and_capture(source)
    assert Enum.any?(diags, &String.contains?(&1.message, "should always come after"))
    refute Enum.any?(diags, &PreferRescueBeforeCatch.match?/1)

    refute Enum.any?(
             Credence.Semantic.analyze(source),
             &(&1.rule == :prefer_rescue_before_catch)
           )
  end

  # No issue: `rescue` already precedes `catch`, so the compiler stays quiet.
  test "no issue when rescue already precedes catch" do
    source = """
    defmodule CredenceRescueOrderAlreadyCorrect do
      def run(f) do
        try do
          f.()
        rescue
          e -> {:rescue, e}
        catch
          :exit, reason -> {:exit, reason}
        end
      end
    end
    """

    {:ok, diags} = RuleHelpers.compile_and_capture(source)
    refute Enum.any?(diags, &PreferRescueBeforeCatch.match?/1)
    refute PreferRescueBeforeCatch.should_report?(@diagnostic, source)
  end

  # No issue: a `try` with only a `catch` section has nothing to reorder.
  test "no issue for a try with catch but no rescue" do
    source = """
    defmodule CredenceRescueOrderCatchOnlyCheck do
      def run(f) do
        try do
          f.()
        catch
          :exit, reason -> {:exit, reason}
        after
          IO.puts("done")
        end
      end
    end
    """

    {:ok, diags} = RuleHelpers.compile_and_capture(source)
    refute Enum.any?(diags, &PreferRescueBeforeCatch.match?/1)
    refute PreferRescueBeforeCatch.should_report?(@diagnostic, source)
  end

  # No issue: the warning can also reach us from a macro expansion, where the
  # file holds no literal out-of-order `try` for the fix to reorder.
  # `should_report?/2` declines rather than report an issue we won't fix.
  test "no issue when the source holds no literal out-of-order try" do
    source = """
    defmodule CredenceRescueOrderNoLiteralTry do
      def run(f), do: f.()
    end
    """

    refute PreferRescueBeforeCatch.should_report?(@diagnostic, source)
  end

  test "should_report? is false when the source does not parse" do
    refute PreferRescueBeforeCatch.should_report?(@diagnostic, "defmodule Broken do")
  end
end
