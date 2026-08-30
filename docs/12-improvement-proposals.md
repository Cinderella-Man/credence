# 12 — Improvement proposals: rule quality, oracles, and the pipeline

> **This document is a SPEC and a HISTORY, not a tracker.** Open work that
> came out of it lives in [`docs/22-remaining-work.md`](22-remaining-work.md),
> and the ordered release map is [`STATUS.md`](../STATUS.md). Where this file
> describes something as open, check there before believing it.

> **Scrutinized 2026-07-11 — see [`docs/14-proposal-scrutiny.md`](14-proposal-scrutiny.md)**
> for experimental validation. Corrections that affect this document: **C1 also
> applies to `NoSortForTopK`** (the battery probe found the same tie bug live in
> its `sort |> reverse |> at(0)` → `Enum.max` mapping); **C7** is re-prioritized
> (measured incidence 1/66 fixed files, and the observed mechanism is
> Pattern-creates-Semantic-work — the cheap fix is an idempotency gate plus one
> Semantic re-pass after Pattern changes, not an intra-Pattern fixpoint);
> **C18** is confirmed by prototype (3/4 mutants killed; the survivor was an
> equivalent mutant — budget triage noise); **C13** gains `prefer_erlang_float`
> as a candidate (37 findings on hand-written gold code).

**Status:** proposal · **Date:** 2026-07-11 · **Scope:** the Credence library —
the fix pipeline, the QA oracles, and the rule set itself. The sister document
[`credence-evolution-harness/docs/IMPROVEMENTS.md`](../../credence-evolution-harness/docs/IMPROVEMENTS.md)
covers the rule *factory*; items that span both are cross-referenced as `H#`.
This document extends the QA roadmap in `docs/11` — where an item overlaps a
roadmap entry, that is noted rather than re-argued.

How this was produced: a full read of the pipeline (`lib/credence.ex`,
`lib/pattern.ex`, `lib/semantic.ex`, `lib/syntax.ex`, `lib/rule_helpers.ex`,
`lib/dsl_guard.ex`), the QA machinery (meta-gates, behaviour-equivalence
harness, corpus suite, fixture healer, maintainer tools), an audit of the 146
Pattern rules (inventory, overlap clusters, ~14 deep reads), git archaeology of
the `evolution` merges (provenance, post-landing bugfixes, the 105 `followup —`
rejection commits), and empirical verification of every defect claim below by
executing the expressions on Elixir 1.20.2.

**What is already strong** (and should not be destabilized): the mandatory
check/fix/equivalence test triplet with meta-gates; byte-exact fix comparison;
the per-rule compile-revert in the Pattern round; the analyze/fix-lockstep DSL
gate; the ~500-entry pinned corpus with a per-finding snapshot ratchet plus
metamorphic fix-safety checks; the fixture healer; and the maintainer review
loops. The proposals below mostly *extend the oracles* — the audit's clearest
lesson is that shipped defects cluster exactly where an oracle has a blind spot,
not where rules are carelessly written.

---

## Tier 1 — verified defects and oracle blind spots

### C1. Fix `no_sort_then_at`'s max-direction tie bug (verified, one-token fix)

**The defect (empirically confirmed).** The rule rewrites
`Enum.sort(c) |> Enum.at(-1)` (and `sort(:desc) |> Enum.at(0)`) to
`Enum.max(c, fn -> nil end)`. A stable ascending sort puts the **last**-seen
maximal element at the end; `Enum.max` returns the **first**-seen maximal
element. For order-equal but `===`-distinct elements — in Elixir that is exactly
mixed `1` vs `1.0` — the two diverge:

```elixir
Enum.sort([1, 1.0]) |> Enum.at(-1)   #=> 1.0
Enum.max([1, 1.0], fn -> nil end)    #=> 1      (1.0 !== 1)
```

The moduledoc claims "the rewrite needs no assumption"
(`lib/pattern/no_sort_then_at.ex:12`); the two min-direction mappings are fine
(first-minimal on both sides).

**The one-token repair (verified exhaustively for the divergence class).** A
strict sorter makes `Enum.max` pick the last-seen maximal:
`Enum.max(c, &>/2, fn -> nil end)` is `===`-identical to both
`Enum.sort(c) |> Enum.at(-1)` and `Enum.sort(c, :desc) |> Enum.at(0)` across
all tie-heavy int/float lists (65/65 brute-forced, 0 divergences; and since
integer-vs-float is the *only* `==`-equal/`===`-distinct class in the language,
this brute force covers the whole divergence class). Change the two
max-direction replacement templates and pin fixtures.

**Why the oracle missed it — and the deeper fix.** The rule's equivalence test
does everything right: it exists, it tests the `at(-1)`/max direction, and it
feeds `EquivalenceInputs.term_lists()` — the very generator built to carry the
value-kind trap. But `term_lists()`' only mixed-kind entry is
`[1, 1.0, 1, 1.0, 2]` (`test/support/equivalence_inputs.ex:27`), whose tie
group sits at the **minimum** while the maximum (`2`) is unique — so the
max-direction bug is invisible to the whole battery by exactly one missing
input. Add mixed-kind entries whose tie group is at the max (e.g. `[1.0, 1]`
and `[1, 2, 2.0]`) to `term_lists()`, then re-run every equivalence test that
uses the dimension and triage anything newly red (any new red is a real
divergence by construction).

**A note on the sibling sort rules (verified safe, but pin it).**
`no_sort_then_reverse` and `no_double_sort_same_list` encode
`Enum.sort(l) |> Enum.reverse() ≡ Enum.sort(l, :desc)`. On Elixir 1.20.2 this
is `===`-exact across 625 brute-forced tie-heavy lists — `:desc` reverses tie
groups exactly as reverse-of-ascending does — so, contrary to first
appearances, these two rules are correct today. But the equivalence rests on
tie behaviour of `sort(:desc)` that the docs do not clearly promise. Add a
**stdlib sentinel test** (a tiny test asserting
`Enum.sort([1, 1.0], :desc) === [1.0, 1]` and friends, with a comment naming
the two rules that depend on it) so an Elixir upgrade that changes tie handling
turns the assumption red instead of silently breaking the rewrite.

### C2. Harden the equivalence oracle (extends docs/11 §1)

The equivalence harness is the project's crown jewel and its highest-leverage
investment target. Four concrete upgrades, in increasing order of effort:

1. **Close the known battery holes.** The max-tie entries from C1; plus new
   dimensions the battery simply lacks: `maps`, `keyword_lists`, `tuples`, and
   a `mixed_numeric` dimension (floats, negative floats, `0.0`/`-0.0`). Today a
   rule rewriting `Map.*`/`Keyword.*` shapes gets no relevant adversarial input
   unless the author hand-rolls one.
2. **Mandatory dimension mapping per operation class.** A meta-test rule: if a
   rule's matcher/fix mentions sort/min/max/comparison → its equivalence test
   must include `term_lists` (with the new tie entries); String/grapheme
   functions → the Unicode dimensions; `Map`/`Keyword` → the new map
   dimensions. Mechanically greppable from the rule source; enforced in
   `equivalence_meta_test.exs` alongside the existing anti-stub gates. This is
   the generalized form of C1's lesson: authors (human and LLM alike) pick the
   generator that names their concern, not the one that carries the trap.
3. **A seeded generative layer.** `EquivalenceInputs`' moduledoc already
   anticipates it ("a StreamData layer, if added later, stays additive and
   non-gating"); `stream_data` is already a test dep. Add
   `assert_equivalent(..., generated: <generator>, seed: <fixed>)` support —
   deterministic via pinned seed, so no flakes — and turn it on additively for
   the highest-risk families first (sort/comparison, string, arithmetic). The
   external evidence is blunt: ~19–35% of LLM rewrites are behaviour-changing
   and a fifth of those pass existing tests; fixed batteries miss what
   generation finds (C1 is a live example in *this* repo).
4. **Fix `mix credence.equiv`'s vacuous verdict + extend its reach** (`H3`).
   With multi-var input and no `--dim`/`--inputs-file`, the battery is `[]` and
   `classify/5` returns EQUIVALENT vacuously (`Enum.all?` over an empty list) —
   make 0 admitted inputs an error/`SKIPPED`, never EQUIVALENT. Then extend to
   multi-var (per-var dimension selection) and a `--module-mode` that reuses
   `assert_equivalent_module`'s compile-under-fresh-names machinery, so the
   harness's classify-time gate stops `:skipped`-ing every structural rewrite.

### C3. Give the Syntax round a safety net (all-or-nothing + centralized parse-gate)

The Syntax round applies raw string→string fixes with **no per-rule revert**,
only logging whether the result parses at the end (`lib/syntax.ex:71-111`). The
`evolution` branch rejected 7+ line-regex rules for corrupting heredoc content;
the two that shipped (`no_markdown_code_fences`, `prefer_cond_do_keyword`) are
safe only because each hand-rolled an anchor + "commit only if it now parses"
gate. That guard is per-rule folklore, not a phase invariant — the next
generated Syntax rule can reintroduce the whole class.

Proposal, two layers:
- **Phase-level all-or-nothing:** if, after all Syntax rules run, the source
  *still* does not parse, return the **original** input for the round instead
  of the accumulated mutations (opt-out flag for callers who want partial
  repairs as retry signal). Today a half-mangled intermediate propagates to the
  caller whenever no rule sequence achieves a parse.
- **Per-rule progress guard in the runner** (not in each rule): keep a rule's
  change only if the result parses, or the first parse-error position moves —
  i.e. demonstrable progress; otherwise revert that rule's change and mark it
  in the trace, mirroring the Pattern round's `:reverted` discipline.

### C4. Compile-revert parity for the Semantic round

Only the Pattern round has a compile-revert. A Semantic rule's
`fix(src, diagnostic)` is accepted unconditionally
(`lib/semantic.ex:144-152`) — a fix that breaks compilation propagates through
the rest of the pass and can be returned to the caller. Cheapest sound version:
compile once per *pass* (the loop already compiles to collect diagnostics); if
a pass's fixes turned a compiling source into a non-compiling one (or grew the
error count), bisect the pass's applied fixes (they are per-diagnostic and
ordered) to find and revert the offender, marking it `:reverted` in the trace.
This closes the asymmetry with one extra compile in the common case.

### C5. Close the analyze/fix desync on the patch self-revert path

`apply_rule_fix` silently discards a fix whose patched output fails to parse or
perturbs the comment multiset (`lib/rule_helpers.ex:279`). The DSL gate
carefully keeps analyze and fix in lockstep — a finding is never reported if
its fix would be dropped — but this second drop path has no analyze-side
counterpart: the finding is **reported yet silently unfixed**, invisible to the
caller (`fixed == source` reads as "no change", no `:reverted` marker). This is
the one undocumented exception to "every Pattern rule fixes what it finds".
Make it visible and consistent: record `{rule, :patch_rejected}` in the trace,
and suppress the finding in the final analyze the same way DSL-dropped findings
are suppressed (or — better for the harness — report it distinctly so the
bugfix lane can consume it, `H1`'s `:reverted` sibling).

### C6. Fault and resource isolation around untrusted input

Two related hardenings for a library whose input is by definition AI-generated
code:

- **Per-rule crash isolation.** `rule.check` and `fix_patches` run bare
  (`lib/pattern.ex:34-41,86`); docs/09 records a shipped rule raising
  `:erlang.length(nil)` on 36 corpus files — one buggy rule crashes the entire
  `analyze`/`fix` call. Wrap per-rule invocation in try/rescue: log, skip the
  rule, add `{rule, :crashed}` to the trace. A crashed rule is a bug to fix,
  but it should cost one rule's findings, not the whole call.
- **Sandboxed compiles.** `compiles?`/`compile_and_capture` run
  `Code.compile_string` in-process with no timeout — compile-time evaluation of
  module bodies means adversarial or merely pathological input can hang or
  side-effect the host VM (`lib/rule_helpers.ex:160-204`). Run compiles in a
  supervised `Task` with a configurable timeout (killing the task on expiry),
  and document the residual trust model. This also gives the Semantic round's
  1–3 compile passes a bound.

---

## Tier 2 — pipeline architecture

### C7. Convergence: a bounded fixpoint option plus an idempotency gate

The Pattern round is a single forward pass in `{priority, module}` order
(`lib/pattern.ex:80`); a rule's fix can create a shape an earlier-ordered rule
would match, and `Credence.fix` returns with that finding merely *reported*.
The grapheme cluster reaches its endpoint today only because
`AvoidGraphemesEnumCount` alphabetically precedes `NoEnumCountForLength` (§C8).
Idempotency (`fix(fix(x)) == fix(x)`) is asserted by exactly one tiny fixture
in `test/credence_pipeline_test.exs:717-737`.

Both mature auto-fixers solved this the same way: ESLint runs up to 10 fix
passes with circular-fix detection; RuboCop loops to stabilization and raises
on infinite loops. Proposal:

1. **`fix(code, passes: n)`** — an outer loop re-running the three rounds until
   no rule fires or `n` (default 1 for compatibility; recommend 3), with
   output-hash cycle detection (compare against two passes ago; on a cycle,
   stop, log the participating rules — that pair is a rule-interaction defect).
2. **An idempotency corpus gate:** for every rule's `_fix_test` input fixtures
   (they are enumerable — the fixture healer already parses them), assert the
   full pipeline converges within 2 passes and `fix∘fix = fix`. Cheap,
   deterministic, and it catches ping-pong pairs and missed-second-chance
   compositions *before* the harness commits a new rule (`H4`'s Gate would
   inherit it via the corpus-free suite).

### C8. An ordering policy instead of ordering-by-accident

139/146 Pattern rules sit at the default priority 500, so ~95% of inter-rule
order is alphabetical accident (`lib/rule_helpers.ex:23`); the 7 non-default
priorities (50/499/501/510/520) are undocumented nudges. Known consequences:
the grapheme/count trio's endpoint depends on the alphabet (maintainer-flagged
in commit `8b750fe` and unresolved). Proposal: (a) write the policy down in
`docs/` (when to claim a band, what bands mean — e.g. repairs < 100, shape
normalizers 200–400, default 500, cleanups that consume other rules' output
600+); (b) give the known feeds-into pairs explicit priorities now; (c) add a
maintainer report task that, for each rule pair, applies rule A's fix to A's
fixtures and checks whether rule B then fires — an empirical feeds-into map to
review at each ruleset milestone (C7's fixpoint makes ordering less load-
bearing, but the map keeps it *intentional*).

### C9. Performance: stop re-parsing 146× and re-discovering rules per call

> **See also `docs/13-test-suite-performance.md`** (added 2026-07-11): a
> measured investigation of the corpus-suite cost specifically — per-entry
> parallelization, sweep sharing, rule-scoped Gate scans, and an AST cache —
> with the numbers behind them. C9 below concerns the fix-pipeline hot path;
> docs/13 measured `discover_rules` at 0.24 ms warm, so treat that sub-item
> as minor.

Measured shape of one `fix` call (`lib/pattern.ex:83`,`:86`;
`lib/rule_helpers.ex:20-24`): 146 `Sourceror.parse_string` calls (one per rule,
even when nothing changed), ~292 `rule.check` walks (fix + final analyze),
K+2–5 full `Code.compile_string` invocations, and `discover_rules`
re-derived from `Application.spec` on every entry. Cheap wins, in order:
parse once and re-parse only after a rule actually changes the source (drops
~145 parses in the no-op case); memoize discovery in `:persistent_term`;
optionally batch the per-fired-rule compile checks (compile every N fixes,
bisect on failure) once C7's loop raises fix counts. None of this changes
semantics; the corpus scan (~8 min) and the harness's per-row validation both
sit directly on this hot path.

### C10. Provenance and observability as API, not log lines

Callers get `applied_rules :: [{module, count | :reverted}]` and debug-level
log side effects; the `Issue` struct carries `rule`/`message`/`meta[:line]`
only — no column, no byte range, no per-rule diff
(`lib/issue.ex:5`; `lib/credence.ex:40-44`). For the harness this means the
entire Classify input rides on a debug log line (`H12`). Proposal: (a) add
`column` to Issue meta (Sourceror ranges already carry it); (b)
`fix_with_trace` gains an opts flag to also return per-rule
`%{rule, patches: [ranges], before_hash, after_hash}`; (c) emit `:telemetry`
events (`[:credence, :fix, :rule_applied | :rule_reverted | :rule_crashed]`)
so consumers can observe without scraping logs. This is also the substrate for
per-rule precision telemetry (C12/C13, `H10`).

---

## Tier 3 — ruleset hygiene

### C11. Fold the known-redundant clusters

- **Grapheme/count trio:** `avoid_graphemes_enum_count`,
  `no_enum_count_for_length`, `avoid_graphemes_length` — three rules, one
  endpoint, alphabet-dependent path (maintainer-acknowledged duplicate,
  `8b750fe`). Fold to two (the count rule + one grapheme rule) or teach one
  rule both shapes.
- **`avoid_length_guard_less_than2`** — documented as duplicating
  `no_length_guard_to_pattern` (`8c4eb9a`) yet shipped; fold or delete.
- **Shared predicates:** `condition_bool?`/`boolean_expr?` are copy-pasted
  verbatim between `no_if_true_false` and `prefer_negate_if_true_false` (the
  latter documents the duplication). Promote to `RuleHelpers` — these two are a
  *model* of coordinated non-overlap and deserve shared, tested plumbing.

The harness-side fix that stops the cluster growing is `H7` (novelty as a
precise blocking gate); this item is the one-time cleanup.

### C12. A generality bar for over-fit rules

The dominant defect signature in the auto-generated bursts is **over-fitting**:
`prefer_map_intersect_over_mapset_intersection` hard-codes one exact four-stage
pipeline plus a specific two-`Map.fetch!` merge;
`prefer_lookup_for_digit_conversion` requires a byte-exact 16-clause hex table;
`prefer_string_slice_for_trim_last_char` matches one 3-clause `case`. All
correct; none will fire on code that isn't the training snippet — dead weight
in a 146-rule hot loop, and rule-count inflation that dilutes the index the
classifier dedups against.

Proposal: (a) **alpha-rename robustness meta-check** — a rule must still fire
on its own `check` fixtures after consistent variable renaming (and, where the
rule doesn't target specific names, function renaming); a matcher keyed to
incidental names fails honestly. (b) **Fire-rate telemetry over feedstock**
(`H10`/`H11` supply the data): a rule that has fired only on its birth row
after N passes is flagged for generalization-or-retirement review. (c) For the
three named rules: retire, or generalize the matcher to the idiom's core (e.g.
"complete literal lookup-table clauses" as a shape, not the hex table
specifically).

### C13. Pay down the corpus whitelist and adopt a per-rule precision budget

The over-firing test's premise is "well-reviewed code, Credence should find
nothing" — but `accepted_findings.txt` holds **6,138 accepted finding lines**,
and the top of the distribution is stark: `prefer_heredoc_for_multi_line_doc`
(1,298), `prefer_map_new` (502), `no_case_true_false` (429),
`prefer_function_capture` (331), `no_underscore_function_name` (226),
`use_map_join` (218). Six rules ≈ half the whitelist. A rule that fires
thousands of times on idiomatic production code is, by the harness's own
NO_ACTION class-1 definition, a *style* rule — precisely what the classify
prompt forbids proposing today. Grandfathered scale also has a real cost:
every accepted finding is a suppressed-fix site and a re-pin burden on every
package bump.

Proposal: (a) a **per-rule accepted-findings budget** (say, 100) enforced as a
meta-test over the snapshot — new rules can't land style-heavy, and existing
over-budget rules get an explicit grandfather list that shrinks; (b) run the
existing `corpus_whitelist_validator` on a cadence and *act* on its reports
(narrow, demote behind an opt-in config, or retire the worst offenders —
`prefer_heredoc_for_multi_line_doc` first); (c) publish the per-rule counts in
the corpus report task so drift is visible per change, Clippy-lintcheck style.
Google's Tricorder threshold is the reference point: analyzer trust collapses
above ~10% noise; a 1,298-finding rule on reviewed code is far past any such
bar.

### C14. Audit DSL-safety coverage for the 132 unclassified rules

The `unsafe_in_dsl` retrofit (PR #20) classified 14 rules — after the whole
class had shipped and fired inside Ash/Ecto/Nx blocks for ~2 months. The
remaining 132 default to "safe everywhere", and the enforcing meta-test
(`DslSafetyClassificationTest`) checks construct-count changes **on each
rule's own fixtures** — a rule whose fixtures don't happen to exhibit the
reinterpreted construct passes silently. Belt-and-braces: a static scan that
flags any rule whose *fix templates/replacement strings* introduce or remove a
reinterpreted token (`!`, `&&`, `==`, `is_nil`, `if`, `case`, arithmetic, …)
without either an `unsafe_in_dsl` declaration or a `@verified_dsl_safe` entry;
cross-check the flag list once by hand. The harness side already teaches new
rules to self-classify (the seed's DSL block); this closes the gap for the
stock.

### C15. One message and moduledoc template

~128/146 rules use multi-line heredoc messages with `# Before`/`# After`; the
rest are one-liners; six rules break the `no_/prefer_/avoid_` prefix
convention; `Issue.meta` is line-only. Adopt a single "rule card" template
(one-sentence intent first — it feeds `Cev.RuleIndex`'s dedup index directly —
then Bad/Good, then the safety argument), enforce message shape and the intent
line via the existing meta-test machinery, and backfill mechanically. Low
effort, and it directly improves the classifier's dedup signal (`H7`/`H8`).

---

## Tier 4 — docs and API housekeeping

### C16. Config and docs debt
- `docs/01` still documents the removed `fix/2` callback and `fixable?/0`, with
  pre-146 rule counts — mark historical or update.
- CHANGELOG has both 0.7.0 and 0.8.1 as "Unreleased".
- Config surface: expose `max_passes` (Semantic), the new compile timeout (C6),
  and fixpoint passes (C7) via `config :credence` alongside the two existing
  keys; document all of them in one place in the README.
- `rule_status/1` could include `priority` and `unsafe_in_dsl` — both are part
  of a rule's observable contract and currently invisible to callers.

---

## Verified-findings appendix

Claims in this document that were verified by execution during the audit
(Elixir 1.20.2):

| Claim | Result |
|---|---|
| `Enum.sort([1,1.0]) \|> Enum.at(-1)` vs `Enum.max([1,1.0], fn -> nil end)` | `1.0` vs `1` — **diverges** (C1) |
| Same, with strict sorter `Enum.max(l, &>/2, fn -> nil end)` | 0 divergences across 65 tie-heavy lists (C1 repair) |
| `Enum.sort(l) \|> Enum.reverse()` vs `Enum.sort(l, :desc)` | `===`-identical across 625 tie-heavy lists — `no_sort_then_reverse` / `no_double_sort_same_list` are **safe today** (sentinel test recommended) |
| `term_lists()` max-group coverage | its only mixed-kind entry ties at the *min*; max-tie inputs absent (C1/C2) |
| Whitelist scale | 6,138 accepted-finding lines; top-6 rules ≈ 50% (C13) |

## Suggested sequencing

| Order | Items | Rationale |
|---|---|---|
| 1 | C1, C5 | A live behaviour bug with a one-token fix; a silent core-promise exception |
| 2 | C2.1–C2.2, C6 | Battery holes + mandatory dimensions; crash/compile isolation — cheap, high leverage |
| 3 | C3, C4 | Round-safety parity (Syntax/Semantic) |
| 4 | C7, C8, C11 | Convergence + ordering policy + cluster folds (one project) |
| 5 | C2.3–C2.4, C13, C12, C14 | Generative equivalence; whitelist paydown; generality bar; DSL audit |
| 6 | C9, C10, C15, C16 | Performance, provenance API, templates, docs |

---

## Addendum (2026-07-11): measurements adopted from `elixir-sft-dataset`

The sibling dataset repo ran a full quality-assurance campaign in 2026-07
(its `docs/10`–`12` + `STATUS.md`) and converged on operational quality
machinery that transfers to this repo almost verbatim. Two new proposals and
two amendments; sources cited into that repo.

### C17. Adopt a versioned Rule Quality Standard + the improvement-round protocol

**The problem it solves here.** Credence's rule set is *era-stratified* the
same way the dataset's corpus was: ~60 pre-evolution rules, two evolution
bursts (~47 + ~39), a DSL-safety guard retrofitted **two months** after the
affected rules shipped (PR #20), an equivalence backfill that was itself a
one-off campaign (docs/07), and a whitelist accumulating debt (C13). Each
past quality upgrade was applied unevenly, and nothing today records which
bar any given rule was accepted under.

**The transferable mechanism** (dataset `docs/12` §3, §7.3, proven over a
3,858-dir corpus):
1. **Write the standard down as a versioned checklist** — "Rule Standard v1":
   test triplet present (already gated) · equivalence dimensions mapped to the
   rule's operation class (C2.2) · DSL-safety classified (C14) · message/
   moduledoc template (C15) · alpha-rename generality (C12) · accepted-corpus-
   findings budget (C13) · semantic-mutant kill floor (C18, once measured).
2. **Raising the bar = a named improvement round**: wire the new check into
   `mix credence.gen.rule` + the meta-gates + the harness seed **first** (so
   every rule born from that moment already meets it — this ordering is
   exactly what prevents the next PR-#20-style retrofit), then run a one-shot
   retrofit sweep over existing rules with its own ledger, verify the whole
   set, **delete the sweep tool**, record the round in a history table.
3. **A `STATUS.md`-style mode file** shared with the harness: is the pair
   *producing rules* or *catching up on a standard bump*? The dataset's
   experience is that this one file stops half-applied upgrades from
   accumulating silently.
4. **Start with the stratification audit table** (dataset `docs/12` §2
   format): one row per out-of-line population — e.g. "132 rules never
   DSL-classified", "rules whose equivalence test uses no operation-mapped
   dimension", "6 rules over the findings budget" — each with size, what's
   missing, and cost to fix. Most of C11–C15 become rows in that table, which
   then *is* the catch-up plan.

### C18. Semantic-mutant tightness score for rule test suites (report → floor)

**The measurement.** The dataset gates harness quality with deterministic
first-order **semantic mutants** of the artifact under test — comparison swap
(`<`↔`<=`, `>`↔`>=`), off-by-one (±1), `:ok`↔`:error`, boolean flip — capped
at 40 per subject, run **report-only** into a ledger with a per-subject kill
rate (`lib/gen_task/mutation.ex:119-201`, `scripts/validate.exs
--semantic-mutants`; corpus kill rate 0.747, and the measured <0.5 tail became
the remediation list). A survived mutant = a behaviour change the tests never
noticed.

**Applied here:** mutate each rule's *implementation* (`check/2` +
`fix_patches/2`) with the same operator set and run only that rule's test
triplet. A surviving mutant means the triplet under-pins the matcher or the
rewrite — precisely the weakness that lets an over-broad or subtly-wrong rule
land. This is docs/11 §3's "mutation-test the rules" roadmap item (currently
NOT DONE) made concrete with a recipe proven in the sibling repo, and it has
manual precedent here: commit `0169116` found two DSL-guard branches missed by
exactly this kind of ad-hoc mutation probing. Rollout the dataset's way:
sweep report-only → publish per-rule kill rates → fix the tail → only then
set a floor as a meta-gate (their evidence: floors set before the tail is
fixed just get ignored). Two cheap riders: a **positive control** (plant a
known-untestable mutant and assert the sweep flags it — the dataset's
"verified non-vacuous" discipline, which credence's equivalence self-tests
already follow and the new gates should too), and a **negative-case floor**
in `check_meta_test` (≥ N non-firing look-alike fixtures per rule, analogous
to their `tests_total >= max(3, public_fn_count)` floor).

### Amendments

- **C13 (whitelist debt)** — adopt the dataset's *evidence-deprioritized
  debt* discipline explicitly: land the budget gate first so the debt stops
  growing, then pay down ranked by evidence (which accepted findings actually
  suppress fixes), and leave the rest as documented, gated debt rather than
  open-ended cleanup (their §4.2.5 pattern).
- **C7/C2 (gates generally)** — every new gate ships with a positive control
  proving it can fail (see C18); a gate nobody has seen red is unverified.
