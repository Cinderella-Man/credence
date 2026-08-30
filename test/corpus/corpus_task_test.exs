defmodule Credence.CorpusTaskTest do
  @moduledoc """
  The command-line contract of `mix credence.corpus --only-rule` (docs/13 P3) —
  the part a Gate depends on and the part that runs without a corpus.

  Two things matter here and neither is cosmetic:

    * a name that is not a live Pattern rule must RAISE, not report zero
      occurrences. "This rule is clean on the corpus" is the exact answer a
      typo would otherwise produce, and it is the answer the Gate acts on; and
    * a Syntax or Semantic rule must be told why it is not scopeable — every
      corpus layer is Pattern-only, so such a candidate needs no corpus scan.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Credence.Corpus, as: CorpusTask

  @rule Credence.Pattern.NoUniqThenCount

  describe "run/1" do
    test "--only-rule dispatches through rule validation before requiring the corpus" do
      error =
        assert_raise Mix.Error, fn ->
          CorpusTask.run(["--only-rule", "Credence.Syntax.FixDivRem"])
        end

      assert error.message ==
               "Credence.Syntax.FixDivRem is not a Pattern rule, and the corpus layer is " <>
                 "Pattern-only (over-firing, fix-safety, scope-parity and fix-breakage all " <>
                 "analyze via Credence.Pattern). A candidate that touches only lib/syntax/ " <>
                 "or lib/semantic/ cannot change any corpus verdict — skip the corpus phase " <>
                 "entirely (docs/13 P3)."
    end
  end

  describe "resolve_rule!/1" do
    test "accepts the snake name" do
      assert CorpusTask.resolve_rule!("no_uniq_then_count").rule_module == @rule
    end

    test "accepts the short Pascal name" do
      assert CorpusTask.resolve_rule!("NoUniqThenCount").rule_module == @rule
    end

    test "accepts the full module, with or without the Elixir. prefix" do
      assert CorpusTask.resolve_rule!("Credence.Pattern.NoUniqThenCount").rule_module == @rule

      assert CorpusTask.resolve_rule!("Elixir.Credence.Pattern.NoUniqThenCount").rule_module ==
               @rule
    end

    test "returns the snake name the snapshot is keyed by" do
      assert CorpusTask.resolve_rule!("NoUniqThenCount").snake == "no_uniq_then_count"
    end

    test "raises on an unknown rule rather than reporting it clean" do
      assert_raise Mix.Error, ~r/unknown Pattern rule/, fn ->
        CorpusTask.resolve_rule!("no_such_rule_at_all")
      end
    end

    test "raises on a rule that exists but is not in the discovered Pattern set" do
      assert_raise Mix.Error, ~r/unknown Pattern rule/, fn ->
        CorpusTask.resolve_rule!("Rule")
      end
    end

    test "tells a Syntax rule that the corpus layer is Pattern-only" do
      assert_raise Mix.Error, ~r/corpus layer is Pattern-only/, fn ->
        CorpusTask.resolve_rule!("Credence.Syntax.FixDivRem")
      end
    end

    test "tells a Semantic rule the same thing" do
      assert_raise Mix.Error, ~r/skip the corpus phase entirely/, fn ->
        CorpusTask.resolve_rule!("Credence.Semantic.FixAfterOrRescueInCase")
      end
    end

    test "raises on a module that is not a Credence rule at all" do
      assert_raise Mix.Error, ~r/not a Credence rule module/, fn ->
        CorpusTask.resolve_rule!("Some.Other.Thing")
      end
    end

    test "every discovered Pattern rule resolves back to itself, in all three forms" do
      for rule <- Credence.Pattern.default_rules() do
        derived = Credence.RuleName.from_module(rule)

        assert CorpusTask.resolve_rule!(derived.snake).rule_module == rule
        assert CorpusTask.resolve_rule!(derived.pascal).rule_module == rule
        assert CorpusTask.resolve_rule!(inspect(rule)).rule_module == rule
      end
    end
  end

  describe "assert_enabled!/3" do
    test "passes for a rule that is on" do
      assert CorpusTask.assert_enabled!(@rule, "no_uniq_then_count", [
               %{rule: @rule, enabled: true, missing: []}
             ]) == :ok
    end

    # A rule switched off by the assumption filter finds nothing, so a scoped
    # scan would print RESULT=clean for a rule that never ran. Vacuous, not
    # wrong — and a Gate cannot tell the two apart, so it has to be loud.
    test "raises for a rule the assumption filter switches off" do
      assert_raise Mix.Error, ~r/switched off under the default assumptions/, fn ->
        CorpusTask.assert_enabled!(@rule, "no_uniq_then_count", [
          %{rule: @rule, enabled: false, missing: [:some_promise]}
        ])
      end
    end

    test "names the missing promises, so the message is actionable" do
      assert_raise Mix.Error, ~r/\[:some_promise\]/, fn ->
        CorpusTask.assert_enabled!(@rule, "no_uniq_then_count", [
          %{rule: @rule, enabled: false, missing: [:some_promise]}
        ])
      end
    end

    test "raises when the requested rule has no status entry" do
      error =
        assert_raise Mix.Error, fn ->
          CorpusTask.assert_enabled!(@rule, "no_uniq_then_count", [])
        end

      assert error.message ==
               "no_uniq_then_count has no assumption status, so a scoped corpus scan cannot " <>
                 "prove that the rule is enabled."
    end

    test "every shipped Pattern rule is scopeable today" do
      statuses = Credence.Pattern.rule_status([])

      for rule <- Credence.Pattern.default_rules() do
        snake = Credence.RuleName.from_module(rule).snake
        assert CorpusTask.assert_enabled!(rule, snake, statuses) == :ok
      end
    end
  end

  describe "assert_complete_corpus!/2" do
    test "raises when even one corpus entry is missing" do
      entries = [{:fetched, "1.0.0"}, {:missing, "2.0.0"}]

      error =
        assert_raise Mix.Error, fn ->
          CorpusTask.assert_complete_corpus!(entries, &(&1 == :fetched))
        end

      assert error.message ==
               "The corpus is incomplete; missing 1 of 2 entries (including missing). " <>
                 "Run `mix credence.corpus.fetch` before using --only-rule."
    end

    test "passes when every corpus entry is fetched" do
      entries = [{:first, "1.0.0"}, {:second, "2.0.0"}]
      assert CorpusTask.assert_complete_corpus!(entries, fn _ -> true end) == :ok
    end
  end

  describe "drift/2" do
    test "no drift when the live findings are the accepted ones" do
      lines = ["a.ex:1  r", "b.ex:2  r"]
      assert CorpusTask.drift(lines, lines) == {[], []}
    end

    test "a finding that is not pinned is NEW — the over-fire signal" do
      assert CorpusTask.drift(["a.ex:1  r", "b.ex:2  r"], ["a.ex:1  r"]) == {["b.ex:2  r"], []}
    end

    test "a pinned finding that stopped firing is GONE — the narrowing signal" do
      assert CorpusTask.drift(["a.ex:1  r"], ["a.ex:1  r", "b.ex:2  r"]) == {[], ["b.ex:2  r"]}
    end

    test "a moved finding is reported in both directions" do
      assert CorpusTask.drift(["a.ex:2  r"], ["a.ex:1  r"]) == {["a.ex:2  r"], ["a.ex:1  r"]}
    end

    test "a brand-new rule with no accepted findings must produce none" do
      assert CorpusTask.drift([], []) == {[], []}
      assert CorpusTask.drift(["a.ex:1  r"], []) == {["a.ex:1  r"], []}
    end
  end
end
