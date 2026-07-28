defmodule Credence.SemanticPassRevertTest do
  # Compiles fixture modules in-process and asserts on `capture_log`, so this
  # module must not interleave with other compile-driven tests.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Credence.{Issue, RuleHelpers}

  # C4. A Semantic pass applies one rule per matched diagnostic and used to
  # accept every result unconditionally: a rule whose `fix/2` broke the source
  # carried the damage into the next pass and out to the caller, recorded in the
  # trace as `{Rule, 1}` — byte-identical to a clean repair. The Pattern round
  # has had a per-rule compile-revert for as long as it has existed; this is the
  # missing half of that parity.
  #
  # The gate cannot be "must compile": this phase runs on non-compiling source
  # by design. The three signals it does use, and the one it deliberately
  # refuses (error COUNT), get a test each below.
  #
  # The rules here are deliberate saboteurs. They are test modules, so
  # `RuleHelpers.discover_rules/1` (which reads `Application.spec(:credence,
  # :modules)`) never sees them; they reach the phase only via the
  # `:semantic_rules` seam.

  defmodule UnusedVarRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :warning, message: msg}) when is_binary(msg),
      do: String.contains?(msg, "is unused")

    def match?(_), do: false

    @impl true
    def to_issue(diag), do: %Issue{rule: :unused_var, message: diag.message, meta: %{line: 3}}

    # A real, correct repair — this rule is the innocent bystander.
    @impl true
    def fix(source, _diag), do: String.replace(source, "unused = 1", "_unused = 1")
  end

  defmodule BreaksCompileRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :warning, message: msg}) when is_binary(msg),
      do: String.contains?(msg, "is undefined (module")

    def match?(_), do: false

    @impl true
    def to_issue(diag), do: %Issue{rule: :breaks_compile, message: diag.message, meta: %{line: 4}}

    # Output still PARSES — only the compiler notices. That is the point: a
    # parse gate alone would wave this through.
    @impl true
    def fix(source, _diag), do: String.replace(source, "Missing.call()", "broken_local()")
  end

  defmodule RepairsWhatBreaksCompileRuleBrokeRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :warning, message: msg}) when is_binary(msg),
      do: String.contains?(msg, "is unused")

    def match?(_), do: false

    @impl true
    def to_issue(diag), do: %Issue{rule: :repairs_it, message: diag.message, meta: %{line: 3}}

    @impl true
    def fix(source, _diag) do
      source
      |> String.replace("broken_local()", "Missing.call()")
      |> String.replace("unused = 1", "_unused = 1")
    end
  end

  defmodule RaisesOnReplayRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :warning, message: msg}) when is_binary(msg),
      do: String.contains?(msg, "is unused")

    def match?(_), do: false

    @impl true
    def to_issue(diag),
      do: %Issue{rule: :raises_on_replay, message: diag.message, meta: %{line: 3}}

    # Only tolerates the mid-pass source `BreaksCompileRule` produced. On the
    # replay — where the culprit's edit is gone — it raises, which is an input it
    # was never called with during the pass itself.
    @impl true
    def fix(source, _diag) do
      if not String.contains?(source, "broken_local()") do
        raise ArgumentError, "boom on replay"
      end

      String.replace(source, "unused = 1", "_unused = 1")
    end
  end

  defmodule BreaksParseRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :error, message: msg}) when is_binary(msg),
      do: String.contains?(msg, "undefined function missing_one/0")

    def match?(_), do: false

    @impl true
    def to_issue(diag), do: %Issue{rule: :breaks_parse, message: diag.message, meta: %{line: 2}}

    @impl true
    def fix(source, _diag), do: String.replace(source, "missing_one()", "do_it(")
  end

  defmodule AddsErrorRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :error, message: msg}) when is_binary(msg),
      do: String.contains?(msg, "undefined function missing_one/0")

    def match?(_), do: false

    @impl true
    def to_issue(diag), do: %Issue{rule: :adds_error, message: diag.message, meta: %{line: 2}}

    # Leaves the error it matched exactly where it was and adds a second one.
    # Still parses, still fails to compile just as before — only the error
    # multiset changed, and only by growing.
    @impl true
    def fix(source, _diag), do: String.replace(source, "# marker", "def b, do: missing_two()")
  end

  @warns """
  defmodule CrdC4_Warns do
    def go do
      unused = 1
      Missing.call()
    end
  end
  """

  @errs """
  defmodule CrdC4_Errs do
    def go, do: missing_one()
  end
  """

  @superset """
  defmodule CrdC4_Superset do
    def a, do: missing_one()
    # marker
  end
  """

  @unmasking """
  defmodule CrdC4_Unmask do
    def a do
      case 1 do
        1 -> :ok
      rescue
        e -> e
      end
    end

    def b, do: missing_one()
    def c, do: missing_two()
  end
  """

  describe "a fix that breaks compilation is reverted and named" do
    test "the culprit is marked :reverted and the innocent rule's fix survives" do
      capture_log(fn ->
        {code, applied} =
          Credence.Semantic.fix_with_trace(@warns,
            semantic_rules: [BreaksCompileRule, UnusedVarRule]
          )

        # The culprit is named. Not the pass, not the phase — the rule.
        assert applied == [{BreaksCompileRule, :reverted}, {UnusedVarRule, 1}]

        # And the bystander's repair is kept: one misbehaving rule costs its own
        # fix, not the pass. This is the Pattern round's discipline.
        assert code =~ "_unused = 1"
        assert code =~ "Missing.call()"
        refute code =~ "broken_local()"
        assert RuleHelpers.compiles?(code)
      end)
    end

    test "the revert is logged at :warning with the rule name" do
      log =
        capture_log(fn ->
          Credence.Semantic.fix_with_trace(@warns,
            semantic_rules: [BreaksCompileRule, UnusedVarRule]
          )
        end)

      assert log =~ "[warning]"
      assert log =~ "the pass made the source WORSE (the source no longer compiles)"
      assert log =~ "BreaksCompileRule: fix made the source worse"
    end

    # The before/after of the reverted fix goes to the row log so the harness's
    # deterministic bugfix lane has a seed to work from. It rides
    # `RuleHelpers.log_diff/3`, which is `:debug` — the same level Pattern's
    # revert path uses, and the level the harness's RowLog handler installs. The
    # suite runs at `:info`, so this has to ask for `:debug` explicitly; without
    # that the assertion silently passes on a level the diff never reaches.
    test "the reverted fix's broken diff reaches the row log at :debug" do
      Logger.configure(level: :debug)

      log =
        capture_log([level: :debug], fn ->
          Credence.Semantic.fix_with_trace(@warns,
            semantic_rules: [BreaksCompileRule, UnusedVarRule]
          )
        end)

      assert log =~ "BreaksCompileRule: source CHANGED"
      assert log =~ "broken_local()"
    after
      Logger.configure(level: :info)
    end

    test "when the culprit is the only fix, the whole pass comes back byte-identical" do
      capture_log(fn ->
        {code, applied} =
          Credence.Semantic.fix_with_trace(@warns, semantic_rules: [BreaksCompileRule])

        assert applied == [{BreaksCompileRule, :reverted}]
        assert code == @warns
      end)
    end
  end

  describe "a fix that breaks parsing is reverted (the phase's own habitat)" do
    test "source that parses but does not compile is not made unparseable" do
      capture_log(fn ->
        {code, applied} =
          Credence.Semantic.fix_with_trace(@errs, semantic_rules: [BreaksParseRule])

        assert applied == [{BreaksParseRule, :reverted}]
        assert code == @errs
      end)
    end

    test "the reason names the parse regression, not a compile one" do
      log =
        capture_log(fn ->
          Credence.Semantic.fix_with_trace(@errs, semantic_rules: [BreaksParseRule])
        end)

      assert log =~ "the source no longer parses"
      refute log =~ "the source no longer compiles"
    end
  end

  describe "a fix that adds an error and repairs none is reverted" do
    # The source does not compile before OR after, and it parses both times, so
    # neither of the first two signals fires. What changed is that every error
    # that was there is still there, verbatim, and a new one joined it.
    test "a strict superset of the pre-pass error multiset is worse" do
      capture_log(fn ->
        {code, applied} =
          Credence.Semantic.fix_with_trace(@superset, semantic_rules: [AddsErrorRule])

        assert applied == [{AddsErrorRule, :reverted}]
        assert code == @superset
      end)
    end

    test "the reason distinguishes it from the parse and compile regressions" do
      log =
        capture_log(fn ->
          Credence.Semantic.fix_with_trace(@superset, semantic_rules: [AddsErrorRule])
        end)

      assert log =~ "it added compile error(s) and repaired none"
    end
  end

  describe "error COUNT is not the measure" do
    # The trap this gate must not fall into. An error that aborts expansion
    # masks every error after it, so a CORRECT repair routinely *raises* the
    # error count as the compiler gets further into the file. Here the shipped
    # `FixAfterOrRescueInCase` turns 2 error diagnostics into 3 — and must not
    # be reverted for it.
    test "a repair that unmasks previously hidden errors is kept" do
      assert error_count(@unmasking) == 2

      capture_log(fn ->
        {code, applied} = Credence.Semantic.fix_with_trace(@unmasking)

        assert {Credence.Semantic.FixAfterOrRescueInCase, 1} in applied
        refute Enum.any?(applied, &match?({_rule, :reverted}, &1))

        # The repair landed...
        assert code =~ "try do"
        # ...and the error count went UP, which a count gate would have called
        # a regression.
        assert error_count(code) == 3
      end)
    end
  end

  describe "the gate never becomes a new way to lose the call" do
    # Replaying the survivors hands each rule the pre-pass source — an input it
    # was not called with during the pass, since the culprit's edit is gone from
    # it. The Semantic round has no per-rule crash isolation, so a rule raising
    # there would otherwise take down a call that previously succeeded.
    test "a rule that raises during the replay degrades to a whole-pass revert" do
      log =
        capture_log(fn ->
          {code, applied} =
            Credence.Semantic.fix_with_trace(@warns,
              semantic_rules: [BreaksCompileRule, RaisesOnReplayRule]
            )

          assert code == @warns
          assert applied == [{BreaksCompileRule, :reverted}, {RaisesOnReplayRule, :reverted}]
        end)

      assert log =~ "replaying the surviving fix(es) raised"
      assert log =~ "boom on replay"
    end
  end

  describe "the gate is per-pass, not per-fix" do
    # A fix is judged by where the pass ended up, not by the state it left
    # behind mid-reduce. Two fixes that only make sense together are therefore
    # allowed; a per-step gate would revert the first and strand the second.
    test "a transiently broken intermediate state is tolerated when the pass lands clean" do
      capture_log(fn ->
        {code, applied} =
          Credence.Semantic.fix_with_trace(@warns,
            semantic_rules: [BreaksCompileRule, RepairsWhatBreaksCompileRuleBrokeRule]
          )

        assert applied == [{BreaksCompileRule, 1}, {RepairsWhatBreaksCompileRuleBrokeRule, 1}]
        refute code =~ "broken_local()"
        assert code =~ "_unused = 1"
        assert RuleHelpers.compiles?(code)
      end)
    end
  end

  describe "the gate is inert when nothing regressed" do
    test "a clean pass keeps the pre-C4 trace shape" do
      capture_log(fn ->
        {code, applied} =
          Credence.Semantic.fix_with_trace(@warns, semantic_rules: [UnusedVarRule])

        assert applied == [{UnusedVarRule, 1}]
        assert code =~ "_unused = 1"
      end)
    end

    test "a rule that matches but returns identical source is still recorded, unreverted" do
      defmodule NoOpRule do
        @moduledoc false
        use Credence.Semantic.Rule

        @impl true
        def match?(%{severity: :warning, message: msg}) when is_binary(msg),
          do: String.contains?(msg, "is unused")

        def match?(_), do: false

        @impl true
        def to_issue(diag), do: %Issue{rule: :no_op, message: diag.message, meta: %{line: 3}}

        @impl true
        def fix(source, _diag), do: source
      end

      capture_log(fn ->
        {code, applied} = Credence.Semantic.fix_with_trace(@warns, semantic_rules: [NoOpRule])

        assert applied == [{NoOpRule, 1}]
        assert code == @warns
      end)
    end
  end

  describe "the :semantic_rules seam" do
    test "analyze/2 honours it too, so check and fix cannot disagree" do
      issues = Credence.Semantic.analyze(@warns, semantic_rules: [UnusedVarRule])

      assert Enum.map(issues, & &1.rule) == [:unused_var]
    end

    test "it defaults to discovery, and the fixtures are never discovered" do
      refute UnusedVarRule in Credence.Semantic.default_rules()
      refute BreaksCompileRule in Credence.Semantic.default_rules()
    end
  end

  defp error_count(source) do
    case RuleHelpers.compile_and_capture(source) do
      {:ok, _diagnostics} -> 0
      {:error, diagnostics} -> Enum.count(diagnostics, &(&1.severity == :error))
    end
  end
end
