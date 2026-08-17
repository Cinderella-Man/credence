defmodule Credence.FixOrDropTest do
  # `async: false`: probes run the full Pattern round, which compiles fixtures.
  use ExUnit.Case, async: false

  alias Credence.FixOrDrop

  @moduledoc """
  **No rule may report a finding that nothing repairs.**

  CONTEXT.md has said "every rule either fixes its problem or it doesn't exist"
  since the beginning, and the maintainer restated it on 2026-08-17: *"if rules
  can't fix the code they need to be removed — we do not have 'warn only' rules,
  Credence is FIXING code, not just complaining about it."* Nothing enforced it.

  ## Why the existing gates could not see this

  `test/no_op_trace_test.exs` (T3.2) makes a no-op *visible* in the trace — it
  proves the vocabulary reports `{rule, :no_op}` rather than staying silent. That
  is a different claim from "no rule does this". A rule could report findings it
  declined to fix and stay green forever, and 24 findings across 9 rules were
  doing exactly that.

  `test/corpus/scope_parity_test.exs` gates the CONVERSE direction: where
  `check/2` is silent, the fix must not act. Nothing gated: where `check/2`
  fires, the fix must act.

  And the coverage figure hides it. Fixture-level fix coverage is **1486/1515 =
  98.1%**, which reads like a rounding error; the 1.9% is real findings a user
  sees reported and never repaired.

  ## Cascades are legitimate and are not counted

  The Pattern round re-parses between rules, so a finding one rule raises can be
  repaired by a sibling. `NoEnumTakeNegative` defers to
  `PreferDescSortOverNegativeTake` on `sort |> take(-n)` deliberately. A no-op is
  only a violation when the FULL round also leaves the source unchanged and the
  rule still reports the finding afterwards. Measured at adoption: 30 no-ops, 6
  cascade-rescued, **24 violations**.

  ## The ledger is a paydown list, not a permission slip

  Every row is a finding a user sees and nothing fixes. The ratchet exists so the
  paydown can happen behind a gate instead of racing one (docs/19 §3: wire the
  check in first, then sweep). It may only SHRINK. There are exactly two ways to
  remove a row — widen the fix so it repairs the case, or narrow `check/2` so it
  stops reporting what the fix will not repair, sharing one predicate between the
  two so they cannot drift (commit 4115c59's remedy). Adding a row is not a
  third way.
  """

  # Frozen 2026-08-17 at 24 violations across 9 rules; 23 remain. May only SHRINK.
  #
  # Paid down the same day:
  #   * `NoRedundantListTraversal` — 13 findings; see below.
  #   * `NoCaseTrueFalse` — 1. `boolean_clause_pair?/2` (check) accepted
  #     wildcard-FIRST orderings that `rewrite_clauses/2` (fix) declined, and
  #     `normalize_pattern/1` was a byte-identical duplicate of
  #     `unwrap_pattern/1` — two copies of one predicate is how they drifted.
  #     Both now go through `fixable_clause_pair/2`.
  #
  # `NoRedundantListTraversal` details: its 13 findings
  # (count+sum pairs it would never merge) are gone, `check/2` and
  # `fix_patches/2` now share `find_fixable_groups/1`, and the corpus lost 6
  # accepted findings with 0 new — a deletions-only re-pin.
  #
  # Reasons, and why they are different defects:
  #   :no_patches     — the fix declined. A scope mismatch between check and fix.
  #   :patch_rejected — the fix emitted patches that `apply_rule_fix_with_status/3`
  #                     DISCARDED because the output did not parse or the comment
  #                     multiset changed. A bug in the fix, not a scope decision.
  #   {:crashed, _}   — `fix_patches/2` raised. Crash isolation makes it silent.
  @ledger [
    {Credence.Pattern.NoGuardEqualityForPatternMatch, "043856d1c848"},
    {Credence.Pattern.NoGuardEqualityForPatternMatch, "1b8090d9e5ff"},
    {Credence.Pattern.NoGuardEqualityForPatternMatch, "ebdfbb4e3c49"},
    {Credence.Pattern.NoListAppendInRecursion, "1e554d1fbc60"},
    {Credence.Pattern.NoListAppendInRecursion, "717abec90223"},
    {Credence.Pattern.NoManualStringReverse, "dd3155e6b3a1"},
    {Credence.Pattern.NoMapKeysOrValuesForIteration, "42bbd80a936a"},
    {Credence.Pattern.NoMapKeysOrValuesForIteration, "e35671a7b522"},
    {Credence.Pattern.NoTrailingNewlineInDoc, "1c4231fc1e36"},
    {Credence.Pattern.NoTrailingNewlineInDoc, "27398e1a89ff"},
    {Credence.Pattern.NoTrailingNewlineInDoc, "53e2070d85d0"},
    {Credence.Pattern.NoTrailingNewlineInDoc, "94395476e95e"},
    {Credence.Pattern.NoTrailingNewlineInDoc, "a0d335190fde"},
    {Credence.Pattern.NoTrailingNewlineInDoc, "aea390ea1b81"},
    {Credence.Pattern.NonGroupedClauses, "71e38a0f00d8"},
    {Credence.Pattern.NonGroupedClauses, "940d04f005ea"},
    {Credence.Pattern.NonGroupedClauses, "b5c1a8b8642f"},
    {Credence.Pattern.NonGroupedClauses, "d50acf813b00"},
    {Credence.Pattern.NonGroupedClauses, "f58078dad656"},
    {Credence.Pattern.NonGroupedClauses, "f7c621ddf5e1"},
    {Credence.Pattern.PreferFunctionClausesForListPatterns, "2e913809e50c"},
    {Credence.Pattern.PreferFunctionClausesForListPatterns, "36f7bb2558bb"},
    {Credence.Pattern.PreferFunctionClausesForListPatterns, "37cfea92ba71"}
  ]

  defp hash(source),
    do: :crypto.hash(:sha256, source) |> Base.encode16(case: :lower) |> binary_part(0, 12)

  # ── The machinery, checked independently of the result ─────────────────────
  #
  # The self-corruption gate taught this the expensive way: its vacuity test
  # asserted "some rule still corrupts", which is correct against a non-empty
  # ledger and worthless at zero — exactly when "nobody violates" and "the probe
  # stopped working" become the same observation from outside. So the vacuity
  # check lives in the MACHINERY, not in the result, and stays meaningful when
  # this ledger reaches empty.

  describe "the probe works regardless of what the ledger says" do
    defmodule AlwaysReportsNeverFixes do
      @moduledoc false
      use Credence.Pattern.Rule

      @impl true
      def check(_ast, _opts),
        do: [%Credence.Issue{rule: :probe_never_fixes, message: "x", meta: %{line: 1}}]

      @impl true
      def fix_patches(_ast, _opts), do: []
    end

    defmodule ReportsAndFixes do
      @moduledoc false
      use Credence.Pattern.Rule

      @impl true
      def check(_ast, _opts),
        do: [%Credence.Issue{rule: :probe_fixes, message: "x", meta: %{line: 1}}]

      @impl true
      def fix_patches(ast, _opts),
        do: Credence.RuleHelpers.patches_from_postwalk(ast, &rename/1)

      defp rename({:probe_before, meta, ctx}) when is_atom(ctx), do: {:probe_after, meta, ctx}
      defp rename(node), do: node
    end

    defmodule FixRaises do
      @moduledoc false
      use Credence.Pattern.Rule

      @impl true
      def check(_ast, _opts),
        do: [%Credence.Issue{rule: :probe_raises, message: "x", meta: %{line: 1}}]

      @impl true
      def fix_patches(_ast, _opts), do: raise(ArgumentError, "probe")
    end

    @src "x = probe_before\n"

    test "a rule that reports and never fixes is caught" do
      assert {:noop, :no_patches} = FixOrDrop.probe(AlwaysReportsNeverFixes, @src)
    end

    test "a rule that reports and fixes is not caught" do
      assert :fixed = FixOrDrop.probe(ReportsAndFixes, @src)
    end

    test "a raising fix is caught, and named as a crash rather than a decline" do
      assert {:noop, {:crashed, ArgumentError}} = FixOrDrop.probe(FixRaises, @src)
    end

    test "a rule whose check is silent is not caught" do
      # `NoEnumSortThenMapValues` cannot fire on this source.
      assert :silent = FixOrDrop.probe(Credence.Pattern.NoEnumSortThenMapValues, @src)
    end

    test "the candidate index is non-empty, so the sweep is not passing over nothing" do
      counts =
        Credence.Pattern.default_rules()
        |> Enum.map(&length(FixOrDrop.fixtures(&1)))

      assert Enum.sum(counts) > 1_000
      assert Enum.count(counts, &(&1 > 0)) > 140
    end
  end

  # ── The ledger polices itself ──────────────────────────────────────────────

  describe "the ledger" do
    test "names only live rules" do
      live = MapSet.new(Credence.Pattern.default_rules())
      stale = @ledger |> Enum.map(&elem(&1, 0)) |> Enum.reject(&MapSet.member?(live, &1))

      assert stale == [], "the ledger names rules that no longer exist: #{inspect(stale)}"
    end

    test "every ledgered row is still a violation" do
      by_rule = Enum.group_by(@ledger, &elem(&1, 0), &elem(&1, 1))

      paid =
        Enum.flat_map(by_rule, fn {rule, hashes} ->
          sources = Map.new(FixOrDrop.fixtures(rule), &{hash(&1), &1})

          Enum.flat_map(hashes, fn h ->
            case Map.fetch(sources, h) do
              :error ->
                ["#{inspect(rule)} #{h} — fixture no longer exists"]

              {:ok, src} ->
                if FixOrDrop.violation?(rule, src), do: [], else: ["#{inspect(rule)} #{h}"]
            end
          end)
        end)

      assert paid == [],
             """
             These are fixed now, so they are no longer debt — delete their rows.

             A ratchet that keeps paid entries stops being a ratchet: the row sits
             there granting permission for a regression to slide back under it.

             #{Enum.join(paid, "\n")}
             """
    end
  end

  # ── The gate ───────────────────────────────────────────────────────────────

  # Deliberately UNTAGGED, so it runs in the default `mix test`.
  #
  # The obvious move is to tag it `:fix_or_drop` and exclude it like the
  # `:idempotency` sweep. Today is the day not to: that sweep was excluded, went
  # red when the Pattern compile gate came off, and nobody noticed across four
  # intervening rules because nothing ran it. The excuse for excluding a sweep is
  # cost, and this one has none — the whole file is 2.7 s, because
  # the fixture index is a handful of parses per rule and the expensive full-round
  # probe only runs for the sources that already no-op.
  @tag timeout: 900_000
  test "no rule reports a finding that nothing repairs" do
    ledgered = MapSet.new(@ledger)

    new =
      Credence.Pattern.default_rules()
      |> FixOrDrop.violations()
      |> Enum.reject(fn {rule, src, _why} -> MapSet.member?(ledgered, {rule, hash(src)}) end)

    assert new == [],
           """
           A rule reports a finding and nothing repairs it. Credence fixes code; it
           does not complain about it (CONTEXT.md: "every rule either fixes its
           problem or it doesn't exist").

           Two ways out, and adding a ledger row is not one of them:

             * WIDEN the fix so it repairs the case; or
             * NARROW `check/2` so it stops reporting what the fix will not repair,
               sharing ONE predicate between check and fix so they cannot drift.

           If the reason is `:patch_rejected` the fix is emitting patches that get
           discarded for non-parsing output or a changed comment multiset — that is
           a bug in the fix, not a scope decision. If it is `{:crashed, _}`, the fix
           raised.

           #{Enum.map_join(new, "\n\n", fn {r, s, why} -> "#{inspect(r)} #{inspect(why)} #{hash(s)}\n#{s}" end)}
           """
  end
end
