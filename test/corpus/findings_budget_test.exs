defmodule Credence.Corpus.FindingsBudgetTest do
  @moduledoc """
  The **corpus-findings budget gate** (docs/12 C13, docs/19 §2 row C, Rule
  Standard item 8) — the frozen policy half of `Credence.Corpus.Budget`.

  ## What this adds that the over-firing test does not

  `test/corpus/over_firing_test.exs` already pins the findings exactly, per
  package, so no rule can start firing on the corpus without going red. That
  ratchets **code** changes. It does not ratchet the **accept**: its own failure
  message says "re-pin with `mix credence.corpus --update-snapshot`", the re-pin
  is one command, and what lands in review is N raw `<path>:<line>  <rule>`
  lines with no per-rule aggregate anywhere. Nothing in the suite has ever
  named a number for a single rule. That is how the snapshot reached **6,366
  accepted findings across 87 rules**, 74% of them in 15 rules and 20% in one.

  This gate is the number. It runs off the two committed files — no corpus
  fetch, no analysis — so it is fast, `async`, and (deliberately) **not** tagged
  `:corpus`: `mix test --exclude corpus` still enforces the budget.

  ## The policy, frozen here on purpose

  `@cap` and `@grandfathered` live in this test rather than in the library, the
  same way `@verified_dsl_safe` lives in `DslSafetyClassificationTest`: they are
  this project's policy about its own corpus, not library behaviour, and the
  only way to loosen either is to edit a gate — visibly, in the diff, with a
  number attached.

  Four invariants, one test each:

    1. the published budget file equals the snapshot's per-rule counts exactly;
    2. a rule **not** on the ledger may not exceed `@cap` — a new rule cannot
       land style-heavy;
    3. a grandfathered rule may not exceed its adoption-day ceiling — those 15
       numbers ratchet down only;
    4. a grandfathered rule that has fallen to `@cap` or below must **leave** the
       ledger — which is what makes the ledger shrink, and makes a paydown
       permanent (off the ledger, the rule can never exceed the cap again
       without a deliberate re-grandfathering).

  ## Why the cap is 100 and not something rounder

  A flat cap that reddens the top of the distribution on day one is not a gate,
  it is a wall (docs/19 §2 row A learned this the expensive way with 129
  newly-red rules). 100 is the number C13 proposes, and the measured
  distribution puts its own knee exactly there: the 15th-largest rule has 122
  accepted findings, the 16th has 99. So the cap sits in a real gap in the data,
  grandfathers precisely the 15 rules holding 74% of the debt, and leaves the
  other 72 firing rules — and the 68 Pattern rules that fire zero times —
  already compliant, with no slack going spare.
  """
  use ExUnit.Case, async: true

  alias Credence.Corpus.{Budget, Findings}

  @cap Budget.default_cap()

  # The grandfather ledger: every rule that was already over the cap when the
  # budget gate was adopted (2026-07-28), pinned at exactly the count it had.
  #
  # There is one reason and it is the same for all fifteen — they predate the
  # gate — so none is written out per rule; inventing fifteen different
  # justifications after the fact would be fiction. What each number means is
  # concrete: a high-water mark that may only fall. A rule that drops to the cap
  # or below must be deleted from this map (invariant 4).
  #
  # These 15 rules hold 4,734 of the 6,366 accepted findings (74%).
  @grandfathered %{
    "prefer_heredoc_for_multi_line_doc" => 1298,
    "no_case_true_false" => 521,
    "prefer_map_new" => 504,
    "prefer_function_capture" => 337,
    "prefer_guard_over_if" => 249,
    "no_underscore_function_name" => 226,
    "no_case_on_param_dispatch" => 222,
    "use_map_join" => 220,
    "prefer_sigil_charlist" => 194,
    "no_case_boolean_result" => 192,
    "no_length_comparison_for_empty" => 174,
    "no_trailing_newline_in_doc" => 167,
    "no_redundant_assignment" => 159,
    "prefer_map_new_with_transform" => 149,
    "no_cond_two_clauses" => 122
  }

  @policy [cap: @cap, grandfathered: @grandfathered]

  setup_all do
    counts = Budget.counts(Findings.snapshot_lines())
    {:ok, counts: counts, published: Budget.published(), violations: violations(counts)}
  end

  defp violations(counts), do: Budget.violations(counts, Budget.published(), @policy)

  defp only(violations, kind), do: Enum.filter(violations, &(elem(&1, 0) == kind))

  defp stale_ceilings(counts, ledger) do
    for {rule, ceiling} <- ledger,
        count = Map.get(counts, rule, 0),
        count > @cap and count < ceiling,
        do: {rule, ceiling, count}
  end

  describe "the gate cannot pass vacuously" do
    test "the accepted-findings snapshot is present and non-empty", %{counts: counts} do
      assert File.exists?(Findings.snapshot_path()),
             "#{Findings.snapshot_path()} is missing — every check below would pass on an " <>
               "empty snapshot, so this is a hard failure rather than a green run."

      assert counts != %{},
             "the snapshot parsed to zero findings. Either it was truncated, or the identity " <>
               "format changed and Findings.rule_of/1 no longer recognises it — in both cases " <>
               "the budget checks below would be vacuously green."
    end

    test "the published budget file is present and non-empty", %{published: published} do
      assert File.exists?(Budget.budget_path()),
             "#{Budget.budget_relpath()} is missing. Generate it (no corpus fetch needed):\n" <>
               "    mix credence.corpus --update-budget"

      assert published != %{}, "#{Budget.budget_relpath()} parsed to zero rules."
    end

    test "every budgeted rule is a live Pattern rule", %{published: published} do
      live =
        Credence.Pattern.default_rules()
        |> Enum.map(&Credence.RuleName.from_module(&1).snake)
        |> MapSet.new()

      stale = published |> Map.keys() |> Enum.reject(&MapSet.member?(live, &1)) |> Enum.sort()

      assert stale == [],
             "#{Budget.budget_relpath()} budgets rules that are not in " <>
               "Credence.Pattern.default_rules/0: #{inspect(stale)}. The over-firing test " <>
               "would catch this too, but only with the corpus fetched — this catches it " <>
               "under `mix test --exclude corpus`."
    end
  end

  describe "the budget holds" do
    test "the published budget equals the snapshot's per-rule counts", %{violations: violations} do
      drift = only(violations, :out_of_sync)
      assert drift == [], Budget.explain(drift)
    end

    test "no rule off the grandfather ledger exceeds the cap", %{violations: violations} do
      over = only(violations, :over_cap)
      assert over == [], Budget.explain(over)
    end

    test "no grandfathered rule exceeds its adoption-day ceiling", %{violations: violations} do
      over = only(violations, :over_grandfather)
      assert over == [], Budget.explain(over)
    end

    test "a grandfathered rule paid down to the cap has left the ledger", %{
      violations: violations
    } do
      graduated = only(violations, :graduated)
      assert graduated == [], Budget.explain(graduated)
    end

    test "no violation of any class, including one added after these tests were written", %{
      violations: violations
    } do
      assert violations == [], Budget.explain(violations)
    end
  end

  describe "the ledger itself" do
    test "a partial paydown above the cap ratchets its ceiling down" do
      assert stale_ceilings(%{"legacy_rule" => 400}, %{"legacy_rule" => 521}) == [
               {"legacy_rule", 521, 400}
             ]
    end

    test "names exactly the rules that are over the cap today", %{counts: counts} do
      over_cap = for {rule, count} <- counts, count > @cap, into: MapSet.new(), do: rule

      assert MapSet.new(Map.keys(@grandfathered)) == over_cap,
             "@grandfathered must be exactly the set of rules over the cap of #{@cap}. " <>
               "Extra entries are refill room for a rule that no longer needs them; missing " <>
               "entries are a rule over the cap with nobody's name on it."
    end

    test "every ceiling equals its rule's count today", %{counts: counts} do
      stale = stale_ceilings(counts, @grandfathered)

      assert stale == [],
             "@grandfathered has refill room after a partial paydown; ratchet each " <>
               "{rule, old ceiling, current count} down: #{inspect(stale)}"
    end

    test "every ceiling is above the cap — a ceiling at or under it belongs off the ledger" do
      low = for {rule, ceiling} <- @grandfathered, ceiling <= @cap, do: {rule, ceiling}
      assert low == []
    end
  end
end
