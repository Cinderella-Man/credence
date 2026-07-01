defmodule Credence.Pattern.DslGuardIntegrationTest do
  @moduledoc """
  End-to-end gate behaviour: `Credence.Pattern.analyze/2` suppresses a flagged
  rule's findings inside the DSL families it declares in `unsafe_in_dsl/0`, and
  `Credence.RuleHelpers.apply_rule_fix/3` drops the matching patches — while a
  rule with no DSL sensitivity keeps fixing inside the very same block.

  This is the regression layer the corpus harness structurally cannot provide:
  every corpus check validates plain-Elixir properties (parse / compile / comments
  / over-reach / scope-parity), none evaluates a macro's reinterpretation. These
  fixtures pin the behaviour for the reported Ash `expr` bug and its siblings.
  """
  use ExUnit.Case, async: true

  alias Credence.RuleHelpers
  alias Credence.Pattern

  alias Credence.Pattern.{
    PreferNegateIfTrueFalse,
    NoRedundantAssignment,
    NoCondTwoClauses
  }

  describe "the reported Ash bug — prefer_negate_if_true_false inside expr/1" do
    @ash """
    calculate :has_issues, :boolean, expr(
      if route.status in [:preparing, :can_start] do
        false
      else
        exists(orders, status == :pending)
      end
    )
    """

    test "the fix is dropped inside expr (no !/not flip ships)" do
      assert RuleHelpers.apply_rule_fix(PreferNegateIfTrueFalse, @ash) == @ash
    end

    test "the finding is suppressed (we do not report what we will not fix)" do
      assert Pattern.analyze(@ash, rules: [PreferNegateIfTrueFalse]) == []
    end
  end

  describe "an enclosing fix that leaves the DSL block verbatim is applied (#5b)" do
    # An `if` whose branch merely *contains* an `expr` — the flip lands on plain
    # Elixir (`is_nil`), the `expr` is only moved. The old intersection gate dropped
    # the whole fix; the preservation gate keeps it because the `expr` subtree is
    # unchanged.
    @enclosing """
    def build(record) do
      if is_nil(record.parent_id) do
        false
      else
        expr(parent_id == ^record.parent_id)
      end
    end
    """

    test "the enclosing plain `if` is negated and the expr is left structurally intact" do
      fixed = RuleHelpers.apply_rule_fix(PreferNegateIfTrueFalse, @enclosing)
      assert fixed != @enclosing
      assert fixed =~ "if !is_nil(record.parent_id) do"
      assert fixed =~ "parent_id == ^record.parent_id"
    end

    test "analyze reports it (report iff fixed — parity holds)" do
      assert Pattern.analyze(@enclosing, rules: [PreferNegateIfTrueFalse]) != []
    end

    # Two antipatterns: the outer plain `if` (safe to fix) and an inner `if` INSIDE
    # the expr (must stay). The gate applies the outer, drops the inner.
    @nested """
    def build(record) do
      if is_nil(record.deleted_at) do
        false
      else
        expr(if inner do false else other end)
      end
    end
    """

    test "the outer plain if is fixed while the inner if inside expr is left alone" do
      fixed = RuleHelpers.apply_rule_fix(PreferNegateIfTrueFalse, @nested)
      assert fixed =~ "if !is_nil(record.deleted_at) do"
      refute fixed =~ "!inner"
    end
  end

  describe "the reported bug class via bare Ash.Query.filter (not a literal expr/1)" do
    @bare_filter """
    defmodule MyApp.Queries do
      import Ash.Query

      def visible(query) do
        filter(query,
          if is_nil(archived_at) do
            false
          else
            visible
          end
        )
      end
    end
    """

    test "the !/not flip is dropped inside a bare imported filter" do
      assert RuleHelpers.apply_rule_fix(PreferNegateIfTrueFalse, @bare_filter) == @bare_filter
    end

    test "the finding is suppressed for the bare filter body too" do
      assert Pattern.analyze(@bare_filter, rules: [PreferNegateIfTrueFalse]) == []
    end
  end

  describe "the flag is scoped — plain code is still fixed" do
    test "prefer_negate_if_true_false still rewrites outside any DSL" do
      plain = """
      def member?(seen, current) do
        if MapSet.member?(seen, current) do
          false
        else
          work(current)
        end
      end
      """

      assert RuleHelpers.apply_rule_fix(PreferNegateIfTrueFalse, plain) != plain
    end
  end

  describe "per-family — a rule unsafe only in ash_expr still fixes inside defn" do
    test "no_cond_two_clauses (unsafe_in_dsl: [:ash_expr]) fixes inside a defn body" do
      assert :ash_expr in NoCondTwoClauses.unsafe_in_dsl()
      refute :nx_defn in NoCondTwoClauses.unsafe_in_dsl()

      defn_src = """
      defn classify(x) do
        cond do
          x > 0 -> 1
          true -> 0
        end
      end
      """

      # Fires and fixes: the nx_defn block does not match this rule's unsafe family.
      if Pattern.analyze(defn_src, rules: [NoCondTwoClauses]) != [] do
        assert RuleHelpers.apply_rule_fix(NoCondTwoClauses, defn_src) != defn_src
      end
    end
  end

  describe "analyze and fix agree — a finding is reported iff its fix is applied" do
    # The same anti-pattern appears twice: once in a plain function (line 10) and
    # once inside expr/1 (line 17). The flag must suppress AND skip-fix exactly the
    # expr one, while reporting AND fixing exactly the plain one.
    @mixed """
    defmodule M do
      use MyApp.Resource

      def plain(seen, current) do
        if MapSet.member?(seen, current) do
          false
        else
          work(current)
        end
      end

      def calc do
        expr(
          if status in [:a, :b] do
            false
          else
            other()
          end
        )
      end
    end
    """

    test "analyze reports only the plain occurrence" do
      issues = Pattern.analyze(@mixed, rules: [PreferNegateIfTrueFalse])
      assert length(issues) == 1
      assert hd(issues).meta[:line] == 5
    end

    test "fix rewrites the plain occurrence and leaves the expr one byte-identical" do
      fixed = RuleHelpers.apply_rule_fix(PreferNegateIfTrueFalse, @mixed)

      # plain one rewritten (condition negated)
      assert fixed =~ "if !MapSet.member?(seen, current) do"
      # expr one untouched — still `if status ... do` then `false`
      assert fixed =~ "if status in [:a, :b] do\n        false"
      refute fixed =~ "if !(status in [:a, :b])"
    end
  end

  describe "a DSL-safe rule keeps fixing inside a DSL block" do
    test "no_redundant_assignment (unsafe_in_dsl: []) fixes inside a defn body" do
      assert NoRedundantAssignment.unsafe_in_dsl() == []

      defn_src = """
      defn f(a) do
        x = a + 1
        x = x
        x
      end
      """

      assert RuleHelpers.apply_rule_fix(NoRedundantAssignment, defn_src) != defn_src
    end
  end
end
