defmodule Credence.RuleCrashIsolationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Credence.Issue

  # C6. `check/2` and `fix_patches/2` run on AI-generated input by definition.
  # A rule that raises on one shape used to take the whole `analyze`/`fix` call
  # down with it — every other rule's findings lost, the caller seeing an
  # exception from a library whose job is to be robust to bad input. docs/09
  # records a shipped rule raising `:erlang.length(nil)` on 36 corpus files.
  #
  # A crashing rule is a bug in that rule. It should cost that rule's findings,
  # not the run.

  defmodule CrashingCheckRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def priority, do: 100

    @impl true
    # opaque to the type checker: the crash must happen at runtime, not be
    # flagged at compile time (that would be the compiler doing our job for us)
    def check(_ast, opts), do: :erlang.length(Keyword.get(opts, :never_set))

    @impl true
    def fix_patches(_ast, _opts), do: []
  end

  defmodule CrashingFixRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def priority, do: 100

    @impl true
    def check(_ast, _opts), do: [%Issue{rule: :crashing_fix, message: "x", meta: %{line: 1}}]

    @impl true
    def fix_patches(_ast, _opts), do: raise(ArgumentError, "boom from fix_patches")
  end

  defmodule ThrowingRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def priority, do: 100

    @impl true
    def check(_ast, _opts), do: throw(:not_an_exception)

    @impl true
    def fix_patches(_ast, _opts), do: []
  end

  defmodule HealthyRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def priority, do: 900

    @impl true
    def check(_ast, _opts), do: [%Issue{rule: :healthy, message: "found", meta: %{line: 2}}]

    @impl true
    def fix_patches(_ast, opts) do
      source = Keyword.fetch!(opts, :source)
      lines = String.split(source, "\n")
      target = Enum.find_index(lines, &String.contains?(&1, "y = 1")) + 1
      len = lines |> Enum.at(target - 1) |> String.length()

      [
        %{
          range: %{start: [line: target, column: 1], end: [line: target, column: len + 1]},
          change: "  y = 2"
        }
      ]
    end
  end

  defmodule CrashingSemanticReportRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{message: message}), do: String.contains?(message, "unused")

    def should_report?(_diagnostic, _source), do: raise("boom from should_report?")

    @impl true
    def to_issue(_diagnostic), do: raise("unreachable")

    @impl true
    def fix(source, _diagnostic), do: source
  end

  defmodule CrashingSemanticFixRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{message: message}), do: String.contains?(message, "unused")

    @impl true
    def to_issue(diagnostic),
      do: %Issue{rule: :crashing_semantic_fix, message: diagnostic.message, meta: %{line: 2}}

    @impl true
    def fix(_source, _diagnostic), do: exit(:boom_from_semantic_fix)
  end

  @source """
  defmodule Sample do
    y = 1
    def go, do: :ok
  end
  """

  # `async: false` on purpose. Run concurrently, these fixture-rule tests are
  # order-sensitive: at seed 484776 the whole trace came back `[]`, so the
  # failure read as "the feature does not work" when in fact the rules had not
  # run. Some other module's global `Application.put_env(:credence, ...)` is the
  # likely culprit — `assumptions_filtering_test` sets `:strict` — but I did not
  # prove which, so this comment claims only the observation. Serialising the
  # module makes it green on that seed and costs ~0.1s.

  describe "analyze/2" do
    test "a crashing rule costs its own findings, not the call" do
      log =
        capture_log(fn ->
          issues =
            Credence.Pattern.analyze(@source,
              rules: [CrashingCheckRule, HealthyRule],
              assumptions: :default
            )

          # The healthy rule's finding survives — that is the whole point.
          assert Enum.map(issues, & &1.rule) == [:healthy]
        end)

      assert log =~ "CrashingCheckRule.check CRASHED"
      assert log =~ "defect in the rule"
    end

    test "a rule that throws a non-exception is isolated too" do
      log =
        capture_log(fn ->
          issues =
            Credence.Pattern.analyze(@source,
              rules: [ThrowingRule, HealthyRule],
              assumptions: :default
            )

          assert Enum.map(issues, & &1.rule) == [:healthy]
        end)

      assert log =~ "threw throw :not_an_exception"
    end
  end

  describe "fix_with_trace/2" do
    test "a rule crashing in check is recorded and later healthy rules still run" do
      capture_log(fn ->
        {code, applied} =
          Credence.Pattern.fix_with_trace(@source,
            rules: [CrashingCheckRule, HealthyRule],
            assumptions: :default
          )

        assert code == "defmodule Sample do\n  y = 2\n  def go, do: :ok\nend\n"
        assert applied == [{CrashingCheckRule, :crashed}, {HealthyRule, 1}]
      end)
    end

    test "a rule crashing in fix_patches is recorded as {rule, :crashed}" do
      capture_log(fn ->
        {code, applied} =
          Credence.Pattern.fix_with_trace(@source,
            rules: [CrashingFixRule, HealthyRule],
            assumptions: :default
          )

        # The crash is visible in the trace, distinct from :reverted and
        # :patch_rejected, so the harness bugfix lane can consume it.
        assert {CrashingFixRule, :crashed} in applied

        # And the healthy rule still did its work on the same call.
        assert {HealthyRule, 1} in applied
        assert code =~ "y = 2"
      end)
    end

    test "the crash is logged at :error, not swallowed" do
      log =
        capture_log(fn ->
          Credence.Pattern.fix_with_trace(@source,
            rules: [CrashingFixRule],
            assumptions: :default
          )
        end)

      assert log =~ "[error]"
      assert log =~ "boom from fix_patches"
    end
  end

  describe "Semantic callback isolation" do
    @semantic_source """
    defmodule SemanticCrashIsolationSubject do
      def run do
        unused = 1
        :ok
      end
    end
    """

    test "a should_report?/2 exception drops only that rule's finding" do
      log =
        capture_log(fn ->
          assert Credence.Semantic.analyze(@semantic_source,
                   semantic_rules: [CrashingSemanticReportRule]
                 ) == []
        end)

      assert log =~ "CrashingSemanticReportRule.should_report? CRASHED"
    end

    test "a fix/2 exit is recorded without crashing the pipeline" do
      log =
        capture_log(fn ->
          assert {code, applied} =
                   Credence.Semantic.fix_with_trace(@semantic_source,
                     semantic_rules: [CrashingSemanticFixRule]
                   )

          assert code == @semantic_source
          assert applied == [{CrashingSemanticFixRule, :crashed}]
        end)

      assert log =~ "CrashingSemanticFixRule.fix threw exit :boom_from_semantic_fix"
    end
  end
end
