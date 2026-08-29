defmodule Credence.NoOpTraceTest do
  @moduledoc """
  T3.2 — a rule whose check fired and whose fix changed nothing must say so.

  Both rounds got this wrong, in opposite directions:

    * **Pattern** dropped the rule from the trace entirely (a `Logger.debug` and
      no entry), so it was indistinguishable from a rule that had nothing to do.
    * **Semantic** recorded `{rule, 1}` — a positive claim that it had fixed one
      diagnostic, which is worse than saying nothing.

  Both now report `{rule, :no_op}`. This matters beyond tidiness because the
  Semantic round is first-match-wins: a rule that matches a diagnostic and then
  declines to act on it is holding a dispatch slot no other rule can have, and
  before this the trace gave no way to see it.

  The trace vocabulary is a cross-repo contract — see `t:Credence.rule_outcome/0`
  and `Credence.rule_outcomes/0`. The last test here pins it as a closed set so
  a future member cannot be added on this side without the change being visible.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Credence.Issue

  # --- Pattern -------------------------------------------------------------

  # Both probes find the same thing — `Enum.count(x)` — so the only difference
  # between the two traces is whether the fix produced anything.
  def count_issues(ast, atom) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [_arg]} = node, acc ->
          {node, [%Issue{rule: atom, message: "Enum.count/1", meta: %{line: meta[:line]}} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  defmodule PatternNoOpRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def check(ast, _opts), do: Credence.NoOpTraceTest.count_issues(ast, :pattern_no_op_probe)

    # Claims a finding, then produces no patches at all.
    @impl true
    def fix_patches(_ast, _opts), do: []
  end

  defmodule PatternRealFixRule do
    @moduledoc false
    use Credence.Pattern.Rule

    @impl true
    def check(ast, _opts), do: Credence.NoOpTraceTest.count_issues(ast, :pattern_real_probe)

    @impl true
    def fix_patches(ast, _opts) do
      Credence.RuleHelpers.patches_from_postwalk(ast, fn
        {{:., meta, [{:__aliases__, _, [:Enum]}, :count]}, _, [arg]} ->
          {:length, meta, [arg]}

        node ->
          node
      end)
    end
  end

  @pattern_source """
  defmodule NoOpProbeSubject do
    def run(list), do: Enum.count(list)
  end
  """

  describe "Pattern round" do
    test "a rule whose check fires and whose fix changes nothing is traced as :no_op" do
      capture_log(fn ->
        {code, applied} =
          Credence.Pattern.fix_with_trace(@pattern_source, rules: [PatternNoOpRule])

        assert applied == [{PatternNoOpRule, :no_op}],
               "before T3.2 this rule vanished from the trace entirely, which made it " <>
                 "indistinguishable from a rule that found nothing to do"

        assert code == @pattern_source
      end)
    end

    test "a rule that really fixes something is still traced with its finding count" do
      capture_log(fn ->
        {code, applied} =
          Credence.Pattern.fix_with_trace(@pattern_source, rules: [PatternRealFixRule])

        assert [{PatternRealFixRule, count}] = applied
        assert is_integer(count) and count > 0
        refute code == @pattern_source
      end)
    end
  end

  # --- Semantic ------------------------------------------------------------

  defmodule SemanticNoOpRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :warning, message: msg}) when is_binary(msg),
      do: String.contains?(msg, "is unused")

    def match?(_), do: false

    @impl true
    def to_issue(d), do: %Issue{rule: :semantic_no_op_probe, message: d.message, meta: %{line: 1}}

    @impl true
    def fix(source, _diagnostic), do: source
  end

  defmodule SemanticLowerPriorityFixRule do
    @moduledoc false
    use Credence.Semantic.Rule

    @impl true
    def match?(%{severity: :warning, message: msg}) when is_binary(msg),
      do: String.contains?(msg, "is unused")

    def match?(_), do: false

    @impl true
    def to_issue(d),
      do: %Issue{rule: :semantic_lower_priority, message: d.message, meta: %{line: 1}}

    @impl true
    def fix(source, _diagnostic), do: String.replace(source, "unused = 1", "wrong = 1")
  end

  @semantic_source """
  defmodule NoOpProbeSemantic do
    def run do
      unused = 1
      :ok
    end
  end
  """

  describe "Semantic round" do
    test "a rule that matches and returns identical source is traced as :no_op, not 1" do
      capture_log(fn ->
        {code, applied} =
          Credence.Semantic.fix_with_trace(@semantic_source, semantic_rules: [SemanticNoOpRule])

        assert applied == [{SemanticNoOpRule, :no_op}],
               "before T3.2 this was reported as `{rule, 1}` — a positive claim that one " <>
                 "diagnostic had been fixed, when the source came back byte-identical"

        assert code == @semantic_source
      end)
    end

    test "a no-op owner does not yield its diagnostic to a lower-priority rule" do
      capture_log(fn ->
        {code, applied} =
          Credence.Semantic.fix_with_trace(@semantic_source,
            semantic_rules: [SemanticNoOpRule, SemanticLowerPriorityFixRule]
          )

        assert code == @semantic_source
        assert applied == [{SemanticNoOpRule, :no_op}]
      end)
    end
  end

  # --- the contract --------------------------------------------------------

  describe "the trace vocabulary is a closed cross-repo contract" do
    test "rule_outcomes/0 is exactly the documented set" do
      assert Credence.rule_outcomes() == [
               :reverted,
               :rolled_back,
               :patch_rejected,
               :crashed,
               :no_op
             ],
             """
             The trace vocabulary changed. This is not a local edit: the evolution
             harness parses these atoms out of the APPLIED_RULES: line, and an
             outcome its regex does not recognise is SILENTLY DROPPED there — the
             rule disappears from the closed set its classifier may name, so a
             correct bug report about that rule becomes unfileable.

             Widen `Cev.AppliedRules`' `@pair` regex in the harness in the same
             change, and update its contract test, before landing this.
             """
    end

    test "every documented outcome is an atom the harness regex shape can carry" do
      # The harness matches outcomes as `:[a-z][a-z0-9_]*`. An outcome outside
      # that shape (uppercase, punctuation) would parse on this side and drop on
      # the other, which is the failure mode that is invisible by construction.
      for outcome <- Credence.rule_outcomes() do
        assert Regex.match?(~r/^[a-z][a-z0-9_]*$/, Atom.to_string(outcome)),
               "#{inspect(outcome)} cannot be carried by the harness's outcome regex " <>
                 "(`:[a-z][a-z0-9_]*`) and would be silently dropped there"
      end
    end
  end
end
